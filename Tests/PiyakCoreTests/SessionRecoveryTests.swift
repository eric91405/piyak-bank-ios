import Foundation
import SwiftData
import Testing
@testable import PiyakCore

@MainActor private final class RecoveryReminders: SessionReminding {
    var requests: [ReminderNotification] = []
    var now = Date()
    func update(snapshot: SessionSnapshot, interval: ReminderInterval, enabled: Bool) {
        requests = ReminderPlan(snapshot: snapshot, intervalMinutes: interval.rawValue, enabled: enabled)?
            .notifications(after: now) ?? []
    }
}

@MainActor private final class RecoveryFixture {
    let container: ModelContainer
    let store: EconomyStore
    let defaults: UserDefaults
    let suite = "PiyakRecovery." + UUID().uuidString
    var now = Date(timeIntervalSince1970: 1_780_012_800)
    var tick: TimeInterval = 100_000
    let reminders = RecoveryReminders()

    init() throws {
        let schema = Schema([CatalogItem.self, OwnedItem.self, PointTransaction.self, WorkSession.self, RewardReceipt.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container.mainContext.autosaveEnabled = false
        store = EconomyStore(context: container.mainContext)
        defaults = UserDefaults(suiteName: suite)!
        reminders.now = now
        try store.migrateRewardsIfNeeded(now: now)
    }

    func controller() -> SessionController {
        SessionController(context: container.mainContext, economy: store, scheduler: reminders,
                          defaults: defaults, now: { self.now }, continuousNow: { self.tick },
                          bootSessionID: { "recovery-boot" })
    }

    func existingSession(age: TimeInterval, wage: Int) throws -> WorkSession {
        let start = now.addingTimeInterval(-age)
        let record = WorkSession(startedAt: start, wage: wage)
        var proof = RewardTracking(date: start, tick: tick - age, working: true, bootSessionID: "recovery-boot")
        proof.wageClockAnchor = RewardClockAnchor(date: start, tick: tick - age, bootSessionID: "recovery-boot")
        try record.setRewardTracking(proof)
        container.mainContext.insert(record)
        try container.mainContext.save()
        return record
    }

    func clean() { defaults.removePersistentDomain(forName: suite) }
}

@Test @MainActor func independentlyRecoveredWindowsCannotCreateTwoActiveSessions() throws {
    let f = try RecoveryFixture(); defer { f.clean() }
    let first = f.controller(), second = f.controller()
    try first.recoverIfNeeded(); try second.recoverIfNeeded()
    try first.start(wage: 10_000); try second.start(wage: 20_000)
    let records = try f.container.mainContext.fetch(FetchDescriptor<WorkSession>())
    #expect(records.count == 1)
    #expect(second.current?.id == first.current?.id)
    #expect(second.snapshot.wage == 10_000)
    let relaunched = f.controller()
    try relaunched.recoverIfNeeded()
    #expect(relaunched.current?.id == first.current?.id)
    f.now += 600; f.tick += 600
    #expect(try second.stop() == 100)
    // Even a stale secondary controller must consult the store after settlement.
    try first.start(wage: 12_000)
    #expect(first.current?.id != records.first?.id)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<WorkSession>(predicate: #Predicate { $0.isActive })).count == 1)
}

@Test @MainActor func duplicateRecoveryPreservesRecordsAndDoesNotDoubleRewards() throws {
    let f = try RecoveryFixture(); defer { f.clean() }
    let older = try f.existingSession(age: 600, wage: 6_000)
    let latest = try f.existingSession(age: 300, wage: 12_000)
    let controller = f.controller()
    try controller.recoverIfNeeded()
    #expect(controller.current?.id == latest.id)
    #expect(controller.recoveryMessage != nil)
    #expect(!older.isActive)
    #expect(older.endedAt == latest.startedAt)
    #expect(older.accrued(until: f.now) == 500)
    #expect(try f.store.balance() == 100)
    f.now += 60; f.tick += 60
    #expect(try controller.stop() == 10)
    #expect(try f.store.balance() == 110)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).count == 2)
    let receiptCount = try f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>()).count
    try f.controller().recoverIfNeeded()
    #expect(try f.store.balance() == 110)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>()).count == receiptCount)
}

@Test @MainActor func duplicateRecoveryFailureRestoresAllRecordsAndReceipts() throws {
    struct SaveFailure: Error {}
    let f = try RecoveryFixture(); defer { f.clean() }
    let older = try f.existingSession(age: 600, wage: 6_000)
    let latest = try f.existingSession(age: 300, wage: 12_000)
    let originals = [older, latest].map { ($0.segmentsData, $0.rewardTrackingData) }
    f.store.save = { throw SaveFailure() }
    let controller = f.controller()
    #expect(throws: SaveFailure.self) { try controller.recoverIfNeeded() }
    #expect(controller.current == nil)
    for (index, record) in [older, latest].enumerated() {
        #expect(record.isActive && record.endedAt == nil)
        #expect(record.segmentsData == originals[index].0)
        #expect(record.rewardTrackingData == originals[index].1)
    }
    #expect(try f.store.balance() == 0)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>()).count == 1)
    f.store.save = { try f.container.mainContext.save() }
    try controller.recoverIfNeeded()
    #expect(controller.current?.id == latest.id)
    #expect(!older.isActive)
}

@Test @MainActor func duplicateRecoveryChoosesLatestAfterClockReconciliation() throws {
    let f = try RecoveryFixture(); defer { f.clean() }
    let older = try f.existingSession(age: 0, wage: 6_000)
    try f.store.transaction {
        _ = try f.store.rewardDate(now: f.now, tick: f.tick, bootSessionID: "recovery-boot")
    }
    // The wall clock moves back one hour before a second window starts work.
    f.tick += 600; f.now -= 3000
    let latest = try f.existingSession(age: 0, wage: 12_000)
    try f.store.transaction {
        var proof = try #require(try latest.rewardTracking())
        proof.anchorDate = try f.store.rewardDate(now: f.now, tick: f.tick, bootSessionID: "recovery-boot")
        try latest.setRewardTracking(proof)
    }
    #expect(older.startedAt > latest.startedAt)
    f.tick += 600; f.now += 600
    let controller = f.controller()
    try controller.recoverIfNeeded()
    #expect(older.startedAt < latest.startedAt)
    #expect(controller.current?.id == latest.id)
    #expect(controller.snapshot.wage == 12_000)
    #expect(older.endedAt == latest.startedAt)
    #expect(!older.isActive && latest.isActive)
    #expect(older.accrued(until: f.now) == 1_000)
    #expect(latest.accrued(until: f.now) == 2_000)
    #expect(try older.rewardTracking()?.working == false)
    #expect(try latest.rewardTracking()?.working == true)
    let totalBefore = try f.store.balance()
    try controller.stop()
    #expect(try f.store.balance() == totalBefore)
}

@Test @MainActor func remoteRefreshReplenishesDeliveredRemindersAndCheckpointsWork() throws {
    let f = try RecoveryFixture(); defer { f.clean() }
    let controller = f.controller()
    controller.notificationsEnabled = true
    controller.interval = .m15
    try controller.start()
    #expect(f.reminders.requests.count == 48)
    f.now += 12 * 3600 + 60; f.tick += 12 * 3600 + 60
    f.reminders.now = f.now
    #expect(f.reminders.requests.allSatisfy { $0.fireDate < f.now })
    controller.refresh()
    #expect(f.reminders.requests.count == 48)
    #expect(f.reminders.requests.allSatisfy { $0.fireDate > f.now })
    #expect(controller.snapshot.capturedAt == f.now)
    #expect(try controller.current?.rewardTracking()?.capturedSeconds == 12 * 3600 + 60)
}
