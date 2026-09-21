import Foundation
import SwiftData
import Testing
@testable import PiyakCore

@MainActor private final class ClockRecoveryReminders: SessionReminding {
    func update(snapshot: SessionSnapshot, interval: ReminderInterval, enabled: Bool) {}
}

@MainActor private final class ClockRecoveryFixture {
    let container: ModelContainer
    let store: EconomyStore
    let defaults: UserDefaults
    let suite = "PiyakClockRecovery." + UUID().uuidString
    var now: Date
    var tick: TimeInterval = 100_000
    var boot = "clock-recovery-boot-1"
    var controller: SessionController!

    init(fractionalStart: TimeInterval = 0) throws {
        now = Date(timeIntervalSince1970: 1_780_012_800 + fractionalStart)
        let schema = Schema([CatalogItem.self, OwnedItem.self, PointTransaction.self,
                             WorkSession.self, RewardReceipt.self])
        container = try ModelContainer(for: schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container.mainContext.autosaveEnabled = false
        store = EconomyStore(context: container.mainContext)
        defaults = UserDefaults(suiteName: suite)!
        try store.migrateRewardsIfNeeded(now: now)
        controller = makeController()
    }

    func makeController() -> SessionController {
        SessionController(context: container.mainContext, economy: store,
                          scheduler: ClockRecoveryReminders(), defaults: defaults,
                          now: { [unowned self] in self.now },
                          continuousNow: { [unowned self] in self.tick },
                          bootSessionID: { [unowned self] in self.boot })
    }

    func advance(_ elapsed: TimeInterval, wallElapsed: TimeInterval? = nil) {
        tick += elapsed
        now += wallElapsed ?? elapsed
    }

    func receipt(for session: WorkSession) throws -> RewardReceipt {
        try #require(container.mainContext.fetch(FetchDescriptor<RewardReceipt>())
            .first { $0.sessionId == session.id })
    }

    func clean() { defaults.removePersistentDomain(forName: suite) }
}

private struct ClockRecoveryDiskFailure: Error {}

@Test @MainActor func backwardClockCanStopWithMeasuredPayAndIndependentRewards() throws {
    for wage in [10_000, EarningsCalculator.maximumWage] {
        let f = try ClockRecoveryFixture(); defer { f.clean() }
        let originalStart = f.now
        try f.store.replaceRecord(nil, segments: [
            .init(start: originalStart.addingTimeInterval(-7200),
                  end: originalStart.addingTimeInterval(-3600), hourlyWage: 12_000)
        ], now: f.now)
        let manual = try #require(f.container.mainContext.fetch(FetchDescriptor<WorkSession>()).first)
        let manualSegments = try manual.decodedSegments()
        let manualStart = manual.startedAt
        try f.controller.start(wage: wage)
        let session = try #require(f.controller.current)
        f.advance(600, wallElapsed: -3000)

        #expect(try f.controller.stop() == 100)
        #expect(f.controller.current == nil)
        #expect(!session.isActive)
        #expect(session.endedAt == f.now)
        #expect(session.accrued(until: f.now) == wage / 6)
        #expect(EarningsCalculator.workingSeconds(session.segments, until: f.now) == 600)
        #expect(try f.store.balance() == 100)
        #expect(try f.receipt(for: session).intervals() == [
            RewardInterval(start: originalStart, end: originalStart.addingTimeInterval(600))
        ])
        #expect(manual.startedAt == manualStart)
        #expect(try manual.decodedSegments() == manualSegments)
        #expect(manual.accrued(until: f.now) == 12_000)
    }
}

@Test @MainActor func backwardClockCheckpointSurvivesRecoveryBeforeStopping() throws {
    let f = try ClockRecoveryFixture(); defer { f.clean() }
    try f.controller.start(wage: 10_000)
    let session = try #require(f.controller.current)
    f.advance(600, wallElapsed: -3000)
    try f.controller.checkpointRewards()
    #expect(session.accrued(until: f.now) == 1666)
    let rebasedStart = session.startedAt

    let recovered = f.makeController()
    try recovered.recoverIfNeeded()
    #expect(recovered.current?.id == session.id)
    #expect(session.startedAt == rebasedStart)
    #expect(recovered.snapshot.amount(at: f.now) == 1666)
    f.advance(300)
    #expect(try recovered.stop() == 150)
    #expect(session.accrued(until: f.now) == 2500)
    #expect(try f.store.balance() == 150)
    #expect(try f.receipt(for: session).intervals().reduce(0) {
        $0 + $1.end.timeIntervalSince($1.start)
    } == 900)
}

@Test @MainActor func pauseAndResumeAcrossClockCorrectionRetainsOnlyWorkingPay() throws {
    let f = try ClockRecoveryFixture(); defer { f.clean() }
    try f.controller.start(wage: 10_000)
    let session = try #require(f.controller.current)
    f.advance(600, wallElapsed: -3000)
    try f.controller.pause()
    #expect(f.controller.snapshot.isPaused)
    #expect(session.accrued(until: f.now) == 1666)
    f.advance(300, wallElapsed: -3300)
    try f.controller.resume()
    #expect(!f.controller.snapshot.isPaused)
    #expect(session.accrued(until: f.now) == 1666)
    f.advance(600)
    #expect(try f.controller.stop() == 200)

    let segments = try session.decodedSegments()
    #expect(segments.map(\.hourlyWage) == [10_000, 0, 10_000])
    #expect(segments.map { $0.end!.timeIntervalSince($0.start) } == [600, 300, 600])
    #expect(session.accrued(until: f.now) == 3333)
    #expect(EarningsCalculator.workingSeconds(segments, until: f.now) == 1200)
    #expect(try f.store.balance() == 200)
}

@Test @MainActor func backwardClockAfterRebootRetainsCheckpointedPayAndSkipsUnknownTime() throws {
    let f = try ClockRecoveryFixture(); defer { f.clean() }
    let originalStart = f.now
    try f.controller.start(wage: 10_000)
    let session = try #require(f.controller.current)
    f.advance(600)
    try f.controller.checkpointRewards()

    f.boot = "clock-recovery-boot-2"
    f.tick = 200_000
    f.now = originalStart.addingTimeInterval(-3600)
    let recovered = f.makeController()
    try recovered.recoverIfNeeded()
    #expect(session.accrued(until: f.now) == 1666)
    #expect(EarningsCalculator.workingSeconds(session.segments, until: f.now) == 600)
    f.advance(300)
    #expect(try recovered.stop() == 150)
    #expect(session.accrued(until: f.now) == 2500)
    #expect(try f.store.balance() == 150)
}

@Test @MainActor func legacyTrackingWithoutWageAnchorCanResumeAfterClockCorrection() throws {
    let f = try ClockRecoveryFixture(); defer { f.clean() }
    try f.controller.start(wage: 10_000)
    let session = try #require(f.controller.current)
    f.advance(600)
    try f.controller.pause()
    // Encode exactly the old tracking representation, without the newly added key.
    let data = try #require(session.rewardTrackingData)
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    json.removeValue(forKey: "wageClockAnchor")
    session.rewardTrackingData = try JSONSerialization.data(withJSONObject: json)
    try f.container.mainContext.save()
    #expect(try session.rewardTracking()?.wageClockAnchor == nil)

    f.advance(300, wallElapsed: -3300)
    let recovered = f.makeController()
    try recovered.recoverIfNeeded()
    #expect(recovered.snapshot.isPaused)
    #expect(session.accrued(until: f.now) == 1666)
    try recovered.resume()
    f.advance(600)
    #expect(try recovered.stop() == 200)
    #expect(session.accrued(until: f.now) == 3333)
    #expect(try f.store.balance() == 200)
}

@Test @MainActor func failedClockCorrectionRestoresTimelineAndTrackingBeforeRetry() throws {
    let f = try ClockRecoveryFixture(); defer { f.clean() }
    try f.controller.start(wage: 10_000)
    let session = try #require(f.controller.current)
    let originalStart = session.startedAt
    let originalSegments = session.segmentsData
    let originalTracking = session.rewardTrackingData
    let marker = try #require(f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>())
        .first { $0.sessionId == "reward-policy-v1" })
    let originalClock = marker.clockData
    f.advance(600, wallElapsed: -3000)
    f.store.save = { throw ClockRecoveryDiskFailure() }

    #expect(throws: ClockRecoveryDiskFailure.self) { try f.controller.stop() }
    #expect(f.controller.current?.id == session.id)
    #expect(session.isActive)
    #expect(session.endedAt == nil)
    #expect(session.startedAt == originalStart)
    #expect(session.segmentsData == originalSegments)
    #expect(session.rewardTrackingData == originalTracking)
    #expect(marker.clockData == originalClock)
    #expect(try f.store.balance() == 0)
    #expect(try f.container.mainContext.fetch(FetchDescriptor<RewardReceipt>()).count == 1)

    f.store.save = { try f.container.mainContext.save() }
    #expect(try f.controller.stop() == 100)
    #expect(session.accrued(until: f.now) == 1666)
    #expect(try f.store.balance() == 100)
}

@Test @MainActor func fractionalClockCorrectionPreservesMaximumWageRounding() throws {
    for fraction in [0.0004, 0.0005, 0.0006, 0.9995] {
        for duration in [6.0012, 6.0032, 6.0048] {
            let ordinary = try ClockRecoveryFixture(fractionalStart: fraction)
            let corrected = try ClockRecoveryFixture(fractionalStart: fraction)
            defer { ordinary.clean(); corrected.clean() }
            try ordinary.controller.start(wage: EarningsCalculator.maximumWage)
            try corrected.controller.start(wage: EarningsCalculator.maximumWage)
            let ordinarySession = try #require(ordinary.controller.current)
            let correctedSession = try #require(corrected.controller.current)
            ordinary.advance(duration)
            corrected.advance(duration, wallElapsed: -3599.9998)
            let ordinaryPoints = try ordinary.controller.stop()
            let correctedPoints = try corrected.controller.stop()
            #expect(ordinaryPoints == 1)
            #expect(correctedPoints == ordinaryPoints)
            #expect(correctedSession.accrued(until: corrected.now)
                    == ordinarySession.accrued(until: ordinary.now))
            #expect(correctedSession.endedAt == corrected.now)
            #expect(correctedSession.startedAt < corrected.now)
        }
    }
}

@Test @MainActor func staleControllerCannotRebaseAFinalizedRecordAfterClockCorrection() throws {
    let f = try ClockRecoveryFixture(); defer { f.clean() }
    try f.controller.start(wage: 10_000)
    let stale = f.makeController()
    try stale.recoverIfNeeded()
    let session = try #require(stale.current)
    f.advance(600)
    #expect(try f.controller.stop() == 100)
    let completedStart = session.startedAt
    let completedEnd = session.endedAt
    let completedSegments = session.segmentsData
    let completedTracking = session.rewardTrackingData
    let completedReceipt = try f.receipt(for: session).intervalsData

    f.advance(300, wallElapsed: -3600)
    try stale.checkpointRewards()
    #expect(session.startedAt == completedStart)
    #expect(session.endedAt == completedEnd)
    #expect(session.segmentsData == completedSegments)
    #expect(session.rewardTrackingData == completedTracking)
    #expect(try f.receipt(for: session).intervalsData == completedReceipt)
    #expect(try f.store.balance() == 100)

    stale.refresh()
    #expect(stale.current == nil)
    #expect(!stale.snapshot.isRunning)
    #expect(stale.snapshot.sessionId == nil)
    #expect(session.segmentsData == completedSegments)
    #expect(session.rewardTrackingData == completedTracking)
}
