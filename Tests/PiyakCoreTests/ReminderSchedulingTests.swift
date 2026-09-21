import Foundation
import Testing
@testable import PiyakCore

private let reminderStart = Date(timeIntervalSince1970: 1_780_012_800)

private func workingReminderSnapshot(start: Date = reminderStart, sessionID: String = "work-1") -> SessionSnapshot {
    SessionSnapshot(isRunning: true, isPaused: false, sessionId: sessionID,
        startedAt: start, accrued: 0, wage: 12_000,
        segments: [WageSegment(start: start, hourlyWage: 12_000)], capturedAt: start)
}

private struct ReminderTestFailure: Error {}

@MainActor
private final class FakeReminderClient: ReminderNotificationClient {
    var now = reminderStart
    var authorized = true
    var entries: [String: ReminderNotification] = [:]
    var added: [ReminderNotification] = []
    var removed: [String] = []
    var attempts = 0
    var failOnAttempt: Int?
    var suspendNextAddition = false
    private var suspendedAddition: CheckedContinuation<Void, Never>?
    private var suspensionObserver: CheckedContinuation<Void, Never>?

    func pendingReminders() async -> [ReminderNotification] {
        entries = entries.filter { $0.value.fireDate > now }
        return Array(entries.values)
    }

    func canSchedule() async -> Bool { authorized }

    func removeReminders(withIdentifiers identifiers: [String]) {
        removed += identifiers
        for id in identifiers { entries.removeValue(forKey: id) }
    }

    func addReminder(_ reminder: ReminderNotification) async throws {
        attempts += 1
        if attempts == failOnAttempt { throw ReminderTestFailure() }
        if suspendNextAddition {
            suspendNextAddition = false
            await withCheckedContinuation { continuation in
                suspendedAddition = continuation
                suspensionObserver?.resume()
                suspensionObserver = nil
            }
        }
        // A notification service operation may complete after Task.cancel().
        entries[reminder.identifier] = reminder
        added.append(reminder)
    }

    func waitUntilAdditionSuspends() async {
        if suspendedAddition != nil { return }
        await withCheckedContinuation { suspensionObserver = $0 }
    }

    func finishSuspendedAddition() {
        suspendedAddition?.resume()
        suspendedAddition = nil
    }

    var ordered: [ReminderNotification] { entries.values.sorted { $0.fireDate < $1.fireDate } }
}

@Test @MainActor func reminderForegroundAndRestartKeepOriginalDueDates() async throws {
    let client = FakeReminderClient()
    let plan = try #require(ReminderPlan(snapshot: workingReminderSnapshot(), intervalMinutes: 15, enabled: true))
    let scheduler = ReminderReconciler(client: client, now: { client.now })
    scheduler.update(plan: plan)
    await scheduler.waitForPendingUpdate()
    #expect(client.entries.count == 48)
    let original = client.ordered
    #expect(original.first?.fireDate == reminderStart.addingTimeInterval(15 * 60))

    client.now += 10 * 60
    scheduler.update(plan: plan)
    await scheduler.waitForPendingUpdate()
    let restartedScheduler = ReminderReconciler(client: client, now: { client.now })
    restartedScheduler.update(plan: plan)
    await restartedScheduler.waitForPendingUpdate()
    #expect(client.ordered == original)
    #expect(client.added.count == 48)
    #expect(client.removed.isEmpty)

    client.now += 10 * 60
    restartedScheduler.update(plan: plan)
    await restartedScheduler.waitForPendingUpdate()
    #expect(client.entries.count == 48)
    #expect(client.ordered.first?.fireDate == reminderStart.addingTimeInterval(30 * 60))
    #expect(client.added.count == 49)
    #expect(client.removed.isEmpty)
}

@Test @MainActor func reminderPermissionRecoveryRetriesTheSamePlan() async throws {
    let client = FakeReminderClient()
    client.authorized = false
    let plan = try #require(ReminderPlan(snapshot: workingReminderSnapshot(), intervalMinutes: 30, enabled: true))
    let scheduler = ReminderReconciler(client: client, now: { client.now })
    scheduler.update(plan: plan)
    await scheduler.waitForPendingUpdate()
    #expect(client.entries.isEmpty)
    client.now += 5 * 60
    client.authorized = true
    scheduler.update(plan: plan)
    await scheduler.waitForPendingUpdate()
    #expect(client.entries.count == 48)
    #expect(client.ordered.first?.fireDate == reminderStart.addingTimeInterval(30 * 60))
    client.authorized = false
    scheduler.update(plan: plan)
    await scheduler.waitForPendingUpdate()
    #expect(client.entries.isEmpty)
    client.authorized = true
    scheduler.update(plan: plan)
    await scheduler.waitForPendingUpdate()
    #expect(client.entries.count == 48)
}

@Test @MainActor func reminderPartialFailureRetriesOnlyMissingRequests() async throws {
    let client = FakeReminderClient()
    client.failOnAttempt = 3
    let plan = try #require(ReminderPlan(snapshot: workingReminderSnapshot(), intervalMinutes: 15, enabled: true))
    let scheduler = ReminderReconciler(client: client, now: { client.now })
    scheduler.update(plan: plan)
    await scheduler.waitForPendingUpdate()
    #expect(client.entries.count == 2)
    let retained = client.ordered
    scheduler.update(plan: plan)
    await scheduler.waitForPendingUpdate()
    #expect(client.entries.count == 48)
    #expect(client.added.count == 48)
    #expect(client.attempts == 49)
    #expect(client.removed.isEmpty)
    #expect(Array(client.ordered.prefix(2)) == retained)
}

@Test @MainActor func exhaustedReminderQueueRefillsWithoutShiftingCadence() async throws {
    let client = FakeReminderClient()
    let plan = try #require(ReminderPlan(snapshot: workingReminderSnapshot(), intervalMinutes: 15, enabled: true))
    let scheduler = ReminderReconciler(client: client, now: { client.now })
    scheduler.update(plan: plan)
    await scheduler.waitForPendingUpdate()
    client.now += 13 * 3600 + 5 * 60
    scheduler.update(plan: plan)
    await scheduler.waitForPendingUpdate()
    #expect(client.entries.count == 48)
    #expect(client.ordered.first?.fireDate == reminderStart.addingTimeInterval(13 * 3600 + 15 * 60))
    #expect(client.ordered.allSatisfy { $0.fireDate > client.now && $0.fireDate <= client.now.addingTimeInterval(24 * 3600) })
}

@Test @MainActor func rapidPauseResumeRemovesAnAddThatFinishedAfterCancellation() async throws {
    let client = FakeReminderClient()
    client.suspendNextAddition = true
    let initial = workingReminderSnapshot()
    let initialPlan = try #require(ReminderPlan(snapshot: initial, intervalMinutes: 15, enabled: true))
    let scheduler = ReminderReconciler(client: client, now: { client.now })
    scheduler.update(plan: initialPlan)
    await client.waitUntilAdditionSuspends()

    scheduler.update(plan: nil)
    client.now += 60
    var resumed = initial
    resumed.segments = [WageSegment(start: reminderStart, end: client.now, hourlyWage: 12_000),
                        WageSegment(start: client.now, hourlyWage: 12_000)]
    let resumedPlan = try #require(ReminderPlan(snapshot: resumed, intervalMinutes: 15, enabled: true))
    scheduler.update(plan: resumedPlan)
    client.finishSuspendedAddition()
    await scheduler.waitForPendingUpdate()
    #expect(client.entries.count == 48)
    #expect(client.ordered.first?.fireDate == client.now.addingTimeInterval(15 * 60))
    #expect(client.removed.count == 1)
    #expect(Set(client.entries.keys).isDisjoint(with: initialPlan.notifications(after: client.now).map(\.identifier)))
}

@Test @MainActor func stoppingDuringAnInFlightAdditionLeavesNoReminders() async throws {
    let client = FakeReminderClient()
    client.suspendNextAddition = true
    let plan = try #require(ReminderPlan(snapshot: workingReminderSnapshot(), intervalMinutes: 15, enabled: true))
    let scheduler = ReminderReconciler(client: client, now: { client.now })
    scheduler.update(plan: plan)
    await client.waitUntilAdditionSuspends()
    scheduler.update(plan: nil)
    client.finishSuspendedAddition()
    await scheduler.waitForPendingUpdate()
    #expect(client.entries.isEmpty)
    #expect(client.added.count == 1)
    #expect(client.removed.count == 1)
}

@Test @MainActor func changingReminderIntervalReplacesOnlyOwnedNotifications() async throws {
    let client = FakeReminderClient()
    let foreign = ReminderNotification(identifier: "another.feature", fireDate: reminderStart.addingTimeInterval(3600),
        title: "다른 알림", body: "유지해야 해요", deepLink: "")
    client.entries[foreign.identifier] = foreign
    let scheduler = ReminderReconciler(client: client, now: { client.now })
    scheduler.update(plan: ReminderPlan(snapshot: workingReminderSnapshot(), intervalMinutes: 15, enabled: true))
    await scheduler.waitForPendingUpdate()
    client.now += 5 * 60
    scheduler.update(plan: ReminderPlan(snapshot: workingReminderSnapshot(), intervalMinutes: 60, enabled: true))
    await scheduler.waitForPendingUpdate()
    #expect(client.entries[foreign.identifier] == foreign)
    let owned = client.ordered.filter { $0.identifier != foreign.identifier }
    #expect(owned.count == 24)
    #expect(owned.first?.fireDate == reminderStart.addingTimeInterval(3600))
    #expect(client.removed.count == 48)
}

@Test func invalidOrInactiveReminderPlansScheduleNothing() {
    var snapshot = workingReminderSnapshot()
    #expect(ReminderPlan(snapshot: snapshot, intervalMinutes: 15, enabled: false) == nil)
    #expect(ReminderPlan(snapshot: snapshot, intervalMinutes: 0, enabled: true) == nil)
    snapshot.isPaused = true
    #expect(ReminderPlan(snapshot: snapshot, intervalMinutes: 15, enabled: true) == nil)
    snapshot.isPaused = false
    snapshot.isRunning = false
    #expect(ReminderPlan(snapshot: snapshot, intervalMinutes: 15, enabled: true) == nil)
}
