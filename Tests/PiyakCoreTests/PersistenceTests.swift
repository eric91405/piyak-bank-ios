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
    var now = Date(timeIntervalSince1970: 1_780_000_000)
    var controller: SessionController!
    init() throws {
        let schema = Schema([CatalogItem.self, OwnedItem.self, PointTransaction.self, WorkSession.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container.mainContext.autosaveEnabled = false
        store = EconomyStore(context: container.mainContext)
        defaults = UserDefaults(suiteName: suite)!
        controller = SessionController(context: container.mainContext, economy: store, scheduler: Reminders(),
                                       defaults: defaults, now: { [unowned self] in self.now })
    }
    func clean() { defaults.removePersistentDomain(forName: suite) }
}
private struct DiskFailure: Error {}

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
    try f.controller.stop(); try f.controller.stop()
    #expect(try f.store.balance() == 15_000)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).count == 1)
}

@Test @MainActor func failedSettlementRollsBackSessionAndLedger() throws {
    let f = try Fixture(); defer { f.clean() }
    try f.controller.start(wage: 10_000)
    f.now += 3600
    f.store.save = { throw DiskFailure() }
    #expect(throws: DiskFailure.self) { try f.controller.stop() }
    #expect(f.controller.current?.isActive == true)
    #expect(f.controller.current?.endedAt == nil)
    #expect(try f.store.balance() == 0)
    f.store.save = { try f.container.mainContext.save() }
    try f.controller.stop()
    #expect(try f.store.balance() == 10_000)
}

@Test @MainActor func recoveryDoesNotDependOnDefaults() throws {
    let f = try Fixture(); defer { f.clean() }
    try f.controller.start(wage: 12_000)
    f.now += 3600
    f.defaults.removeObject(forKey: AppConfig.kActiveSession)
    let recovered = SessionController(context: f.container.mainContext, economy: f.store,
                                      scheduler: Reminders(), defaults: f.defaults, now: { f.now })
    try recovered.recoverIfNeeded()
    #expect(recovered.current?.id == f.controller.current?.id)
    #expect(recovered.snapshot.amount(at: f.now) == 12_000)
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

@Test @MainActor func editAndDeleteReconcileLedger() throws {
    let f = try Fixture(); defer { f.clean() }
    let start = f.now.addingTimeInterval(-7200)
    try f.store.replaceRecord(nil, segments: [.init(start: start, end: start.addingTimeInterval(3600), hourlyWage: 10_000)], now: f.now)
    let record = try #require(f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).first)
    try f.store.replaceRecord(record, segments: [.init(start: start, end: f.now, hourlyWage: 10_000)], now: f.now)
    #expect(try f.store.balance() == 20_000)
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
    #expect(gown.price == 40_000)
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
    #expect(try f.store.balance() == 10_000)
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
    #expect(try f.store.balance() == 10_000)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).count == 1)
    #expect(throws: DiskFailure.self) { try f.store.resetAll() }
    #expect(try f.store.balance() == 10_000)
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

@Test @MainActor func legacyAccrualRepairIsIdempotentAndPreservesPurchases() throws {
    let f = try Fixture(); defer { f.clean() }
    let record = WorkSession(startedAt: f.now.addingTimeInterval(-3600), wage: 10_000)
    record.endedAt = f.now
    record.isActive = false
    record.segments = [.init(start: record.startedAt, end: f.now, hourlyWage: 10_000)]
    f.container.mainContext.insert(record)
    f.container.mainContext.insert(PointTransaction(amount: 9999, kind: .accrual, date: f.now, relatedId: record.id))
    f.container.mainContext.insert(PointTransaction(amount: -1000, kind: .purchase, relatedId: "existing.item"))
    f.container.mainContext.insert(OwnedItem(catalogId: "existing.item"))
    try f.container.mainContext.save()
    try f.store.reconcileCompletedAccruals()
    try f.store.reconcileCompletedAccruals()
    #expect(try f.store.balance() == 9000)
    #expect(try f.store.owned("existing.item") != nil)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<PointTransaction>()).count == 2)
}
