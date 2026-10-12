import Foundation
import SwiftData
import Testing
@testable import PiyakCore

@MainActor private final class SettlementReminders: SessionReminding {
    func update(snapshot: SessionSnapshot, interval: ReminderInterval, enabled: Bool) {}
}

@MainActor private final class SettlementFixture {
    let container: ModelContainer
    let store: EconomyStore
    let defaults: UserDefaults
    let suite = "PiyakSettlement." + UUID().uuidString
    var now = Date(timeIntervalSince1970: 1_780_012_800)
    var tick: TimeInterval = 100_000
    var controller: SessionController!

    init(storeURL: URL? = nil) throws {
        let schema = Schema([CatalogItem.self, OwnedItem.self, PointTransaction.self,
                             WorkSession.self, RewardReceipt.self])
        let configuration = storeURL.map { ModelConfiguration(url: $0) }
            ?? ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: configuration)
        container.mainContext.autosaveEnabled = false
        store = EconomyStore(context: container.mainContext)
        defaults = UserDefaults(suiteName: suite)!
        try store.migrateRewardsIfNeeded(now: now)
        controller = makeController()
    }

    func makeController() -> SessionController {
        SessionController(context: container.mainContext, economy: store,
                          scheduler: SettlementReminders(), defaults: defaults,
                          now: { [unowned self] in self.now },
                          continuousNow: { [unowned self] in self.tick },
                          bootSessionID: { "settlement-boot" })
    }

    func advance(_ seconds: TimeInterval) { now += seconds; tick += seconds }

    func settle() throws -> WorkSettlement {
        try controller.stop(expectedSessionID: #require(controller.current?.id))
    }

    func ledger(for result: WorkSettlement) throws -> [PointTransaction] {
        try container.mainContext.fetch(FetchDescriptor<PointTransaction>())
            .filter { $0.kind == .accrual && $0.relatedId == result.sessionID }
            .sorted { $0.date < $1.date }
    }

    func clean() { defaults.removePersistentDomain(forName: suite) }
}

@Test @MainActor func settlementNoticeMatchesLedgerAndBalanceAfterPurchases() throws {
    let f = try SettlementFixture(); defer { f.clean() }
    try f.store.seedIfNeeded()
    try f.store.transaction {
        f.container.mainContext.insert(PointTransaction(amount: 1_000, kind: .adjust))
        f.container.mainContext.insert(PointTransaction(amount: 99_999, kind: .legacy))
    }
    try f.store.purchase("wallDeco.clock")
    try f.controller.start(wage: 1_000_000)
    f.advance(600)

    let result = try f.settle()
    #expect(result.points == 100)
    #expect(result.balanceBefore == 550)
    #expect(result.balanceAfter == 650)
    #expect(result.balanceAfter - result.balanceBefore == result.points)
    #expect(try f.store.balance() == result.balanceAfter)
    #expect(try f.ledger(for: result).map(\.amount) == result.accruals.map(\.points))
    #expect(result.message(at: f.now).contains("총 100 P"))
    #expect(result.message(at: f.now).contains("550 P → 650 P"))
}

@Test @MainActor func overnightNoticeExplainsTotalAndEachKSTWorkDay() throws {
    let f = try SettlementFixture(); defer { f.clean() }
    let firstDay = try #require(RewardPolicy.calendar.date(from:
        DateComponents(year: 2026, month: 10, day: 12)))
    f.now = firstDay.addingTimeInterval(23 * 3600)
    try f.controller.start(wage: 10_000)
    f.advance(2 * 3600)

    let result = try f.settle()
    #expect(result.points == 1_200)
    #expect(result.accruals.map(\.points) == [600, 600])
    #expect(result.accruals.map(\.day) == [firstDay, firstDay.addingTimeInterval(24 * 3600)])
    #expect(result.balanceAfter - result.balanceBefore == result.points)
    #expect(try f.ledger(for: result).map(\.date) == result.accruals.map(\.day))
    let message = result.message(at: f.now)
    #expect(message.contains("총 1,200 P"))
    #expect(message.contains("10월 12일: 600 P"))
    #expect(message.contains("10월 13일: 600 P"))
}

@Test @MainActor func priorDayOnlySettlementStillExplainsItsWorkDate() throws {
    let f = try SettlementFixture(); defer { f.clean() }
    let firstDay = try #require(RewardPolicy.calendar.date(from:
        DateComponents(year: 2026, month: 10, day: 12)))
    f.now = firstDay.addingTimeInterval(23 * 3600)
    try f.controller.start()
    f.advance(600)
    try f.controller.pause()
    f.advance(3600)

    let result = try f.settle()
    #expect(result.points == 100)
    #expect(result.accruals.count == 1)
    #expect(result.message(at: f.now).contains("10월 12일: 100 P"))
    #expect(!result.message(at: f.now).contains("10월 13일:"))
}

@Test @MainActor func cappedAndZeroSettlementsReportOnlyActualBalanceIncrease() throws {
    let f = try SettlementFixture(); defer { f.clean() }
    try f.controller.start()
    f.advance(7 * 3600)
    #expect(try f.settle().points == 4_200)
    try f.controller.start()
    f.advance(2 * 3600)
    let capped = try f.settle()
    #expect(capped.points == 600)
    #expect(capped.balanceAfter - capped.balanceBefore == 600)
    try f.controller.start()
    f.advance(600)
    let zero = try f.settle()
    #expect(zero.points == 0)
    #expect(zero.accruals.isEmpty)
    #expect(zero.balanceBefore == 4_800 && zero.balanceAfter == 4_800)
    #expect(zero.message(at: f.now).contains("추가된 포인트는 없어요"))
    #expect(try f.ledger(for: zero).isEmpty)
}

@Test @MainActor func pauseRecoveryAndShortSessionCarryKeepNoticeEqualToLedger() throws {
    let f = try SettlementFixture(); defer { f.clean() }
    try f.controller.start()
    f.advance(3)
    #expect(try f.settle().points == 0)
    f.advance(60)
    try f.controller.start()
    f.advance(3)
    try f.controller.pause()
    f.advance(3600)
    f.controller = f.makeController()
    try f.controller.recoverIfNeeded()
    #expect(f.controller.snapshot.isPaused)
    try f.controller.resume()
    f.advance(600)

    let result = try f.settle()
    #expect(result.points == 101)
    #expect(result.balanceAfter - result.balanceBefore == 101)
    #expect(try f.ledger(for: result).map(\.amount) == [101])
}

@Test @MainActor func stalePhoneConfirmationCannotEndReplacementSession() throws {
    let f = try SettlementFixture(); defer { f.clean() }
    try f.controller.start()
    let confirmedID = try #require(f.controller.current?.id)
    f.advance(600)
    #expect(try f.controller.stop() == 100)
    try f.controller.start()
    let replacementID = try #require(f.controller.current?.id)
    f.advance(600)

    #expect(throws: SessionController.RemoteError.self) {
        try f.controller.stop(expectedSessionID: confirmedID)
    }
    #expect(f.controller.current?.id == replacementID)
    #expect(f.controller.snapshot.isRunning)
    #expect(try f.store.balance() == 100)
    #expect(try f.settle().points == 100)
}

@Test @MainActor func alreadyFinishedConfirmationDoesNotAnnounceZeroPointSuccess() throws {
    let f = try SettlementFixture(); defer { f.clean() }
    try f.controller.start()
    let confirmedID = try #require(f.controller.current?.id)
    f.advance(600)
    let result = try f.settle()
    #expect(throws: SessionController.RemoteError.self) {
        try f.controller.stop(expectedSessionID: confirmedID)
    }
    #expect(try f.store.balance() == result.balanceAfter)
    #expect(try f.ledger(for: result).count == 1)
}

@Test @MainActor func failedSaveReturnsNoSettlementAndRetryAwardsExactlyOnce() throws {
    struct SaveFailure: Error {}
    let f = try SettlementFixture(); defer { f.clean() }
    try f.controller.start()
    f.advance(600)
    f.store.save = { throw SaveFailure() }
    #expect(throws: SaveFailure.self) { try f.settle() }
    #expect(f.controller.current?.isActive == true)
    #expect(try f.store.balance() == 0)
    f.store.save = { try f.container.mainContext.save() }
    let result = try f.settle()
    #expect(result.points == 100)
    #expect(result.balanceBefore == 0 && result.balanceAfter == 100)
    #expect(try f.ledger(for: result).count == 1)
}

@Test @MainActor func settlementBalanceAndDayAmountsSurviveDiskStoreReopen() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "PiyakSettlement-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let f = try SettlementFixture(storeURL: directory.appending(path: "test.store")); defer { f.clean() }
    try f.controller.start()
    f.advance(600)
    let result = try f.settle()

    let reopened = try ModelContainer(for: f.container.schema,
                                     configurations: ModelConfiguration(url: directory.appending(path: "test.store")))
    let persisted = EconomyStore(context: reopened.mainContext)
    #expect(try persisted.balance() == result.balanceAfter)
    let ledger = try reopened.mainContext.fetch(FetchDescriptor<PointTransaction>())
        .filter { $0.kind == .accrual && $0.relatedId == result.sessionID }
    #expect(ledger.reduce(0) { $0 + $1.amount } == result.points)
    #expect(ledger.map(\.date) == result.accruals.map(\.day))
}
