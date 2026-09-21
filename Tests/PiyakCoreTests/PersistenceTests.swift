import Foundation
import SwiftData
import Testing
@testable import PiyakCore

@MainActor private final class Reminders: SessionReminding {
    var snapshot = SessionSnapshot.empty
    func update(snapshot: SessionSnapshot, interval: ReminderInterval, enabled: Bool) { self.snapshot = snapshot }
}
@MainActor private final class Fixture {
    let container: ModelContainer
    let store: EconomyStore
    let defaults: UserDefaults
    let suite = "PiyakTests." + UUID().uuidString
    // 09:00 KST / 00:00 UTC keeps ordinary tests within both local dates.
    var now = Date(timeIntervalSince1970: 1_780_012_800)
    var continuousTime: TimeInterval?
    var bootID = "test-boot-1"
    var controller: SessionController!
    init(migrateRewards: Bool = true, beforeReset: @escaping () throws -> Void = {}) throws {
        let schema = Schema([CatalogItem.self, OwnedItem.self, PointTransaction.self, WorkSession.self, RewardReceipt.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container.mainContext.autosaveEnabled = false
        store = EconomyStore(context: container.mainContext)
        defaults = UserDefaults(suiteName: suite)!
        if migrateRewards { try store.migrateRewardsIfNeeded(now: now) }
        controller = SessionController(context: container.mainContext, economy: store, scheduler: Reminders(),
                                       defaults: defaults, now: { [unowned self] in self.now },
                                       continuousNow: { [unowned self] in self.continuousTime ?? self.now.timeIntervalSince1970 },
                                       bootSessionID: { [unowned self] in self.bootID }, beforeReset: beforeReset)
    }
    func clean() { defaults.removePersistentDomain(forName: suite) }
}
private struct DiskFailure: Error {}

@Test @MainActor func failedLegacyCleanupLeavesActiveRecordsAndRewardsIntact() throws {
    let f = try Fixture(beforeReset: { throw DiskFailure() }); defer { f.clean() }
    try f.store.seedIfNeeded()
    try f.controller.start(wage: 10_000)
    f.now += 60
    try f.controller.stop()
    let balance = try f.store.balance()
    try f.controller.start()
    let currentID = f.controller.current?.id
    #expect(throws: DiskFailure.self) { try f.controller.resetAll() }
    #expect(f.controller.current?.id == currentID)
    #expect(f.defaults.string(forKey: AppConfig.kActiveSession) == currentID)
    #expect(try f.store.balance() == balance)
    #expect(try f.store.ownedAll().count == 4)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).count == 2)
}

@Test @MainActor func startPauseResumeStopIsIdempotent() throws {
    let f = try Fixture(); defer { f.clean() }
    try f.controller.start(wage: 10_000)
    try f.controller.start(wage: 20_000)
    f.now += 3600
    try f.controller.pause(); try f.controller.pause()
    f.now += 3600
    try f.controller.resume(); try f.controller.resume()
    f.now += 1800
    #expect(try f.store.dailyAccrued(on: f.now, includingActive: true, now: f.now) == 15_000)
    #expect(try f.controller.stop() == 900)
    #expect(try f.controller.stop() == 0)
    #expect(try f.store.balance() == 900)
    #expect(try f.store.dailyAccrued(on: f.now) == 15_000)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).count == 1)
}

@Test @MainActor func failedSettlementRollsBackSessionAndLedger() throws {
    let f = try Fixture(); defer { f.clean() }
    try f.controller.start(wage: 10_000)
    f.now += 3600
    let receiptCount = try f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>()).count
    f.store.save = { throw DiskFailure() }
    #expect(throws: DiskFailure.self) { try f.controller.stop() }
    #expect(f.controller.current?.isActive == true)
    #expect(f.controller.current?.endedAt == nil)
    #expect(try f.store.balance() == 0)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>()).count == receiptCount)
    f.store.save = { try f.container.mainContext.save() }
    #expect(try f.controller.stop() == 600)
    #expect(try f.store.balance() == 600)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>()).count == receiptCount + 1)
}

@Test @MainActor func recoveryDoesNotDependOnDefaults() throws {
    let f = try Fixture(); defer { f.clean() }
    try f.controller.start(wage: 12_000)
    f.now += 3600
    f.defaults.removeObject(forKey: AppConfig.kActiveSession)
    let recovered = SessionController(context: f.container.mainContext, economy: f.store,
                                      scheduler: Reminders(), defaults: f.defaults, now: { f.now },
                                      continuousNow: { f.now.timeIntervalSince1970 },
                                      bootSessionID: { f.bootID })
    try recovered.recoverIfNeeded()
    #expect(recovered.current?.id == f.controller.current?.id)
    #expect(recovered.snapshot.amount(at: f.now) == 12_000)
    let record = try #require(recovered.current)
    let settledAt = f.now
    #expect(try recovered.stop() == 600)
    f.now += 1800
    #expect(try f.controller.stop() == 0)
    #expect(try f.store.balance() == 600)
    #expect(record.endedAt == settledAt)
    #expect(record.accrued(until: f.now) == 12_000)
}

@Test @MainActor func failedPurchaseDoesNotGrantItemOrSpendPoints() throws {
    let f = try Fixture(); defer { f.clean() }
    try f.store.seedIfNeeded()
    f.container.mainContext.insert(PointTransaction(amount: 50_000, kind: .adjust))
    try f.container.mainContext.save()
    f.store.save = { throw DiskFailure() }
    #expect(throws: DiskFailure.self) { try f.store.purchase("wallDeco.clock") }
    #expect(try f.store.owned("wallDeco.clock") == nil)
    #expect(try f.store.balance() == 50_000)
}

@Test @MainActor func manualRecordsAndEditsNeverAwardPoints() throws {
    let f = try Fixture(); defer { f.clean() }
    let start = f.now.addingTimeInterval(-7200)
    try f.store.replaceRecord(nil, segments: [.init(start: start, end: start.addingTimeInterval(3600), hourlyWage: 10_000)], now: f.now)
    let record = try #require(f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).first)
    try f.store.replaceRecord(record, segments: [.init(start: start, end: f.now, hourlyWage: 10_000)], now: f.now)
    #expect(record.accrued(until: f.now) == 20_000)
    #expect(try f.store.balance() == 0)
    try f.store.deleteRecord(record)
    #expect(try f.store.balance() == 0)
}

@Test @MainActor func staleWatchCommandCannotStopNewSession() throws {
    let f = try Fixture(); defer { f.clean() }
    try f.controller.start()
    let oldID = f.controller.current?.id
    f.now += 10
    try f.controller.stop()
    try f.controller.start()
    let command = WatchCommand(action: "stop", sessionId: oldID, createdAt: f.now)
    #expect(throws: SessionController.RemoteError.self) { try f.controller.handleRemoteCommand(command) }
    #expect(f.controller.current != nil)
}

@Test @MainActor func preferencesPersistAndFreeCatalogMigrates() throws {
    let f = try Fixture(); defer { f.clean() }
    f.controller.preferredWage = 15_000
    f.controller.interval = .m30
    try f.store.seedIfNeeded()
    let gown = try #require(try f.store.catalog("bodyFront.graduation_gown"))
    gown.isIAP = true
    try f.container.mainContext.save()
    try f.store.seedIfNeeded()
    #expect(gown.isIAP == false)
    #expect(gown.price == 2_000)
    #expect(try f.store.catalog("wallDeco.clock")?.price == 450)
    let other = SessionController(context: f.container.mainContext, economy: f.store, scheduler: Reminders(), defaults: f.defaults)
    #expect(other.preferredWage == 15_000)
    #expect(other.interval == .m30)
}

@Test @MainActor func failedRecordEditRestoresLiveModel() throws {
    let f = try Fixture(); defer { f.clean() }
    let start = f.now.addingTimeInterval(-7200)
    try f.store.replaceRecord(nil, segments: [.init(start: start, end: start.addingTimeInterval(3600), hourlyWage: 10_000)], now: f.now)
    let record = try #require(f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).first)
    f.store.save = { throw DiskFailure() }
    #expect(throws: DiskFailure.self) {
        try f.store.replaceRecord(record, segments: [.init(start: start, end: f.now, hourlyWage: 20_000)], now: f.now)
    }
    #expect(record.accrued(until: f.now) == 10_000)
    #expect(try f.store.balance() == 0)
}

@Test @MainActor func failedDeleteAndResetPreserveRecords() throws {
    let f = try Fixture(); defer { f.clean() }
    try f.store.seedIfNeeded()
    try f.controller.start(wage: 10_000)
    f.now += 3600
    try f.controller.stop()
    let record = try #require(f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).first)
    f.store.save = { throw DiskFailure() }
    #expect(throws: DiskFailure.self) { try f.store.deleteRecord(record) }
    #expect(try f.store.balance() == 600)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).count == 1)
    #expect(throws: DiskFailure.self) { try f.store.resetAll() }
    #expect(try f.store.balance() == 600)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).count == 1)
    #expect(try f.store.ownedAll().count == 4)
}

@Test @MainActor func failedEquipRestoresPreviousOutfit() throws {
    let f = try Fixture(); defer { f.clean() }
    try f.store.seedIfNeeded()
    f.container.mainContext.insert(PointTransaction(amount: 50_000, kind: .adjust))
    try f.container.mainContext.save()
    try f.store.purchase("bodyFront.overalls")
    f.store.save = { throw DiskFailure() }
    #expect(throws: DiskFailure.self) { try f.store.equip("bodyFront.overalls") }
    #expect(try f.store.equippedMap()["bodyFront"] == "bodyFront.hoodie_mint")
}

@Test @MainActor func expiredCommandAndDuplicateCannotAlterState() throws {
    let f = try Fixture(); defer { f.clean() }
    let command = WatchCommand(action: "start", createdAt: f.now)
    try f.controller.handleRemoteCommand(command)
    try f.controller.handleRemoteCommand(command)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).count == 1)
    let stale = WatchCommand(action: "stop", sessionId: f.controller.current?.id, createdAt: f.now.addingTimeInterval(-31))
    #expect(throws: SessionController.RemoteError.self) { try f.controller.handleRemoteCommand(stale) }
    #expect(f.controller.current != nil)
}

@Test @MainActor func inflatingWageChangesPayButNeverTimerRewards() throws {
    for wage in [10_000, 1_000_000] {
        let f = try Fixture(); defer { f.clean() }
        try f.controller.start(wage: wage)
        f.now += 3600
        f.controller.refreshSnapshot()
        #expect(f.controller.snapshot.amount(at: f.now) == wage)
        #expect(try f.store.dailyAccrued(on: f.now, includingActive: true, now: f.now) == wage)
        #expect(try f.controller.stop() == 600)
        #expect(try f.store.balance() == 600)
        #expect(f.controller.snapshot.completedToday == wage)
    }
}

@Test @MainActor func partialTimerPointsCarryBetweenSessions() throws {
    let f = try Fixture(); defer { f.clean() }
    try f.controller.start(wage: 10_000)
    f.now += 3
    #expect(try f.controller.stop() == 0)
    f.now += 60
    try f.controller.start(wage: 1_000_000)
    f.now += 3
    #expect(try f.controller.stop() == 1)
    #expect(try f.store.balance() == 1)
}

@Test @MainActor func dailyCapSurvivesMultipleSessionsAndPurchases() throws {
    let f = try Fixture(); defer { f.clean() }
    try f.store.seedIfNeeded()
    try f.controller.start(wage: 10_000)
    f.now += 7 * 3600
    #expect(try f.controller.stop() == 4_200)
    try f.store.purchase("wallDeco.clock")
    #expect(try f.store.balance() == 3_750)
    try f.controller.start(wage: 10_000)
    f.now += 3 * 3600
    #expect(try f.controller.stop() == 600)
    try f.controller.start(wage: 10_000)
    f.now += 3600
    #expect(try f.controller.stop() == 0)
    #expect(try f.store.balance() == 4_350)
    #expect(try f.store.dailyAccrued(on: f.now) == 110_000)
    #expect(try f.store.owned("wallDeco.clock") != nil)
}

@Test @MainActor func overnightSettlementSharesTheCapWithBothDays() throws {
    let f = try Fixture(); defer { f.clean() }
    let day = try #require(RewardPolicy.calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
    f.now = day.addingTimeInterval(8 * 3600)
    try f.controller.start(wage: 10_000)
    f.now += 7 * 3600
    #expect(try f.controller.stop() == 4_200)
    f.now = day.addingTimeInterval(23 * 3600)
    try f.controller.start(wage: 10_000)
    f.now += 2 * 3600
    #expect(try f.controller.stop() == 1_200)
    #expect(try f.store.balance() == 5_400)
    try f.controller.start(wage: 10_000)
    f.now += 8 * 3600
    #expect(try f.controller.stop() == 4_200)
    #expect(try f.store.balance() == 9_600)
}

@Test @MainActor func editingDeletingAndRecreatingPayRecordCannotMintRewards() throws {
    let f = try Fixture(); defer { f.clean() }
    let start = f.now
    try f.controller.start(wage: 10_000)
    let id = try #require(f.controller.current?.id)
    f.now += 3600
    #expect(try f.controller.stop() == 600)
    let record = try #require(f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).first)
    let receipt = try #require(f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>()).first { $0.sessionId == id })
    let originalIntervals = receipt.intervalsData
    let originalCreatedAt = receipt.createdAt
    f.now += 3600
    let edited: [WageSegment] = [.init(start: start, end: f.now, hourlyWage: 1_000_000)]
    try f.store.replaceRecord(record, segments: edited, now: f.now)
    #expect(record.accrued(until: f.now) == 2_000_000)
    #expect(try f.store.balance() == 600)
    #expect(receipt.intervalsData == originalIntervals)
    #expect(receipt.createdAt == originalCreatedAt)
    try f.store.deleteRecord(record)
    #expect(try f.store.balance() == 600)
    try f.store.replaceRecord(nil, segments: edited, now: f.now)
    #expect(try f.store.balance() == 600)
    let preserved = try f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>()).filter { $0.sessionId == id }
    #expect(preserved.count == 1)
    #expect(preserved.first?.intervalsData == originalIntervals)
}

@Test @MainActor func failedTimerRecordEditPreservesPayAndFinalizedReceipt() throws {
    let f = try Fixture(); defer { f.clean() }
    let start = f.now
    try f.controller.start(wage: 10_000)
    let id = try #require(f.controller.current?.id)
    f.now += 3600
    try f.controller.stop()
    let record = try #require(f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).first)
    let receipt = try #require(f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>()).first { $0.sessionId == id })
    let originalIntervals = receipt.intervalsData
    f.now += 3600
    f.store.save = { throw DiskFailure() }
    #expect(throws: DiskFailure.self) {
        try f.store.replaceRecord(record, segments: [.init(start: start, end: f.now, hourlyWage: 1_000_000)], now: f.now)
    }
    #expect(record.accrued(until: f.now) == 10_000)
    #expect(receipt.intervalsData == originalIntervals)
    #expect(try f.store.balance() == 600)
}

@Test @MainActor func deviceClockJumpsCannotInflateMeasuredRewards() throws {
    for wallSeconds in [12.0 * 3600, 1800.0] {
        let f = try Fixture(); defer { f.clean() }
        f.continuousTime = 100_000
        try f.controller.start(wage: 1_000_000)
        // One real hour passes; the user moves the wall clock ahead or back.
        f.continuousTime! += 3600
        f.now += wallSeconds
        #expect(try f.controller.stop() == 600)
        #expect(try f.store.balance() == 600)
    }
}

@Test @MainActor func unattendedSessionRewardsAtMostTwentyFourMeasuredHours() throws {
    let f = try Fixture(); defer { f.clean() }
    f.now = try #require(RewardPolicy.calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
    try f.controller.start(wage: 10_000)
    f.now += 72 * 3600
    #expect(try f.controller.stop() == 4_800)
    #expect(try f.store.balance() == 4_800)
    let record = try #require(f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).first)
    #expect(record.accrued(until: f.now) == 720_000)
}

@Test @MainActor func legacyActiveSessionStartsRewardTrackingAtUpgrade() throws {
    let f = try Fixture(migrateRewards: false); defer { f.clean() }
    let legacy = WorkSession(startedAt: f.now.addingTimeInterval(-8 * 3600), wage: 1_000_000)
    f.container.mainContext.insert(legacy)
    try f.container.mainContext.save()
    try f.store.migrateRewardsIfNeeded(now: f.now)
    try f.controller.recoverIfNeeded()
    f.now += 3600
    #expect(try f.controller.stop() == 600)
    #expect(try f.store.balance() == 600)
    #expect(legacy.accrued(until: f.now) == 9_000_000)
}

@Test @MainActor func legacyRewardMigrationIsIdempotentAndPreservesPurchasesAndPay() throws {
    let f = try Fixture(migrateRewards: false); defer { f.clean() }
    let record = WorkSession(startedAt: f.now.addingTimeInterval(-3600), wage: 10_000)
    record.endedAt = f.now
    record.isActive = false
    record.segments = [.init(start: record.startedAt, end: f.now, hourlyWage: 10_000)]
    f.container.mainContext.insert(record)
    f.container.mainContext.insert(PointTransaction(amount: 9999, kind: .accrual, date: f.now, relatedId: record.id))
    f.container.mainContext.insert(PointTransaction(amount: -1000, kind: .purchase, relatedId: "existing.item"))
    f.container.mainContext.insert(OwnedItem(catalogId: "existing.item", equippedSlot: .headTop))
    try f.container.mainContext.save()
    try f.store.migrateRewardsIfNeeded(now: f.now)
    let firstReceiptCount = try f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>()).count
    let firstTransactionCount = try f.container.mainContext.fetch(FetchDescriptor<PointTransaction>()).count
    try f.store.migrateRewardsIfNeeded(now: f.now)
    #expect(try f.store.balance() == 449)
    #expect(record.accrued(until: f.now) == 10_000)
    #expect(try f.store.owned("existing.item")?.equippedSlot == .headTop)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>()).count == firstReceiptCount)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<PointTransaction>()).count == firstTransactionCount)
    let transactions = try f.container.mainContext.fetch(FetchDescriptor<PointTransaction>())
    #expect(transactions.filter { $0.kind == .legacy }.count == 2)
    #expect(transactions.filter { $0.kind == .accrual }.isEmpty)
    try f.controller.start(wage: 10_000)
    f.now += 3600
    #expect(try f.controller.stop() == 600)
    try f.store.migrateRewardsIfNeeded(now: f.now)
    #expect(try f.store.balance() == 1_049)
}

@Test @MainActor func migrationCapsLegacyBalanceAndNeverCreatesDebt() throws {
    for (oldBalance, expectedBalance) in [(-100, 0), (19, 0), (20, 1), (95_999, 4_799), (1_000_000_000, 4_800)] {
        let f = try Fixture(migrateRewards: false); defer { f.clean() }
        f.container.mainContext.insert(PointTransaction(amount: oldBalance, kind: .adjust))
        try f.container.mainContext.save()
        try f.store.migrateRewardsIfNeeded(now: f.now)
        #expect(try f.store.balance() == expectedBalance)
    }
}

@Test @MainActor func failedRewardMigrationRollsBackLedgerAndCanBeRetried() throws {
    let f = try Fixture(migrateRewards: false); defer { f.clean() }
    let tx = PointTransaction(amount: 10_000, kind: .accrual)
    f.container.mainContext.insert(tx)
    f.container.mainContext.insert(OwnedItem(catalogId: "existing.item"))
    try f.container.mainContext.save()
    f.store.save = { throw DiskFailure() }
    #expect(throws: DiskFailure.self) { try f.store.migrateRewardsIfNeeded(now: f.now) }
    #expect(tx.kind == .accrual)
    #expect(try f.store.balance() == 10_000)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<PointTransaction>()).count == 1)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>()).isEmpty)
    #expect(try f.store.owned("existing.item") != nil)
    f.store.save = { try f.container.mainContext.save() }
    try f.store.migrateRewardsIfNeeded(now: f.now)
    try f.store.migrateRewardsIfNeeded(now: f.now)
    #expect(try f.store.balance() == 500)
    #expect(tx.kind == .legacy)
}

@Test @MainActor func resettingDataPreservesPolicyMarkerForFutureEarnings() throws {
    let f = try Fixture(); defer { f.clean() }
    try f.store.seedIfNeeded()
    try f.controller.start(wage: 10_000)
    let oldSessionId = try #require(f.controller.current?.id)
    f.now += 3600
    #expect(try f.controller.stop() == 600)
    try f.store.purchase("wallDeco.clock")
    try f.controller.resetAll()
    #expect(try f.store.balance() == 0)
    #expect(try f.store.owned("wallDeco.clock") == nil)
    #expect(try f.store.ownedAll().count == 4)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).isEmpty)
    let resetReceipts = try f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>())
    #expect(!resetReceipts.contains { $0.sessionId == oldSessionId })
    #expect(resetReceipts.count == 1)
    #expect(try resetReceipts.first?.intervals().isEmpty == true)

    try f.controller.start(wage: 10_000)
    let newSessionId = try #require(f.controller.current?.id)
    f.now += 3600
    #expect(try f.controller.stop() == 600)
    try f.store.migrateRewardsIfNeeded(now: f.now)
    #expect(try f.store.balance() == 600)
    let receipt = try #require(f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>()).first { $0.sessionId == newSessionId })
    #expect(try RewardPolicy.total(receipt.intervals(), calendar: RewardPolicy.calendar) == 600)
    let transactions = try f.container.mainContext.fetch(FetchDescriptor<PointTransaction>())
    #expect(transactions.filter { $0.kind == .legacy }.isEmpty)
    #expect(transactions.filter { $0.kind == .accrual }.map(\.amount) == [600])
}

@Test @MainActor func wallClockReplayCreditsOnlyNewElapsedTime() throws {
    let f = try Fixture(); defer { f.clean() }
    let start = f.now
    f.continuousTime = 100_000
    try f.controller.start(wage: 10_000)
    let originalId = try #require(f.controller.current?.id)
    f.now += 3600
    f.continuousTime! += 3600
    #expect(try f.controller.stop() == 600)
    let originalRecord = try #require(f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).first)
    try f.store.deleteRecord(originalRecord)

    // Replaying a wage-record date must neither duplicate its reward interval nor
    // deny a new real hour. The persisted reward clock advances independently.
    f.now = start
    try f.controller.start(wage: 1_000_000)
    let duplicateId = try #require(f.controller.current?.id)
    f.now += 3600
    f.continuousTime! += 3600
    #expect(try f.controller.stop() == 600)
    #expect(try f.store.balance() == 1_200)
    let receipts = try f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>())
    let original = try #require(receipts.first { $0.sessionId == originalId })
    let duplicate = try #require(receipts.first { $0.sessionId == duplicateId })
    let originalInterval = try #require(try original.intervals().last)
    let duplicateInterval = try #require(try duplicate.intervals().first)
    #expect(originalInterval.end <= duplicateInterval.start)
    #expect(duplicateInterval.end.timeIntervalSince(duplicateInterval.start) == 3600)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).count == 1)
}

@Test @MainActor func changingDeviceDateCannotReopenTheDailyRewardCap() throws {
    let f = try Fixture(); defer { f.clean() }
    let originalDay = RewardPolicy.calendar.startOfDay(for: f.now)
    f.continuousTime = 100_000
    try f.controller.start(wage: 10_000)
    f.now += 8 * 3600
    f.continuousTime! += 8 * 3600
    #expect(try f.controller.stop() == 4_800)

    // Moving the device to tomorrow does not advance the persisted reward date.
    f.now += 24 * 3600
    try f.controller.start(wage: 1_000_000)
    f.now += 3600
    f.continuousTime! += 3600
    #expect(try f.controller.stop() == 0)

    // The same protection holds when a clock change is observed by a lifecycle
    // checkpoint during an active session, not just by start or stop.
    try f.controller.start(wage: 1_000_000)
    f.now += 24 * 3600
    try f.controller.checkpointRewards()
    f.now += 3600
    f.continuousTime! += 3600
    try f.controller.checkpointRewards()
    #expect(try f.controller.stop() == 0)
    #expect(try f.store.balance() == 4_800)
    let earned = try f.container.mainContext.fetch(FetchDescriptor<PointTransaction>()).filter { $0.kind == .accrual }
    #expect(earned.map(\.date) == [originalDay])
    let receipts = try f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>())
    let intervals = try receipts.flatMap { try $0.intervals() }
    let days = RewardPolicy.daily(intervals, calendar: RewardPolicy.calendar)
    #expect(days.map(\.day) == [originalDay])
    #expect(days.map(\.points) == [4_800])
}

@Test @MainActor func rebootRebasesRewardDayEvenWhenNewUptimeIsHigher() throws {
    let f = try Fixture(); defer { f.clean() }
    let firstDay = RewardPolicy.calendar.startOfDay(for: f.now)
    f.continuousTime = 100_000
    try f.controller.start(wage: 10_000)
    f.now += 8 * 3600
    f.continuousTime! += 8 * 3600
    #expect(try f.controller.stop() == 4_800)

    // A later boot can already have a greater uptime than the previous checkpoint.
    // Its distinct boot identity, not an uptime decrease, identifies the new day.
    f.now += 2 * 24 * 3600
    f.bootID = "test-boot-2"
    f.continuousTime = 200_000
    let rebootDay = RewardPolicy.calendar.startOfDay(for: f.now)
    try f.controller.start(wage: 10_000)
    f.now += 3600
    f.continuousTime! += 3600
    #expect(try f.controller.stop() == 600)
    #expect(try f.store.balance() == 5_400)
    let transactions = try f.container.mainContext.fetch(FetchDescriptor<PointTransaction>()).filter { $0.kind == .accrual }
    #expect(transactions.map(\.date).sorted() == [firstDay, rebootDay])
}

@Test @MainActor func rebootRecoveryKeepsCheckpointsAndSkipsUnmeasurableGap() throws {
    let f = try Fixture(); defer { f.clean() }
    let firstStart = f.now
    f.continuousTime = 100_000
    try f.controller.start(wage: 10_000)
    let id = try #require(f.controller.current?.id)
    f.now += 3600
    f.continuousTime! += 3600
    try f.controller.checkpointRewards()
    let preRebootEnd = f.now

    f.now += 2 * 24 * 3600
    f.bootID = "test-boot-2"
    f.continuousTime = 200_000
    let resumedAt = f.now
    let recovered = SessionController(context: f.container.mainContext, economy: f.store,
                                      scheduler: Reminders(), defaults: f.defaults, now: { f.now },
                                      continuousNow: { f.continuousTime! },
                                      bootSessionID: { f.bootID })
    try recovered.recoverIfNeeded()
    #expect(recovered.current?.id == id)
    f.now += 3600
    f.continuousTime! += 3600
    #expect(try recovered.stop() == 1_200)
    #expect(try f.store.balance() == 1_200)
    let receipt = try #require(f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>()).first { $0.sessionId == id })
    #expect(try receipt.intervals() == [
        RewardInterval(start: firstStart, end: preRebootEnd),
        RewardInterval(start: resumedAt, end: f.now)
    ])
}
