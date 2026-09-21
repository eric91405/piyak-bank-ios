import Foundation
import SwiftData
import Combine
#if os(iOS)
import WidgetKit
#endif

@MainActor
protocol SessionSyncing: AnyObject {
    func didUpdateSession(_ snapshot: SessionSnapshot)
}

@MainActor
protocol SessionReminding: AnyObject {
    func update(snapshot: SessionSnapshot, interval: ReminderInterval, enabled: Bool)
}

enum ReminderInterval: Int, CaseIterable { case m15 = 15, m30 = 30, m60 = 60 }

@MainActor
final class SessionController: ObservableObject {
    @Published private(set) var current: WorkSession?
    @Published private(set) var snapshot = SessionSnapshot.empty
    @Published var errorMessage: String?
    @Published var recoveryMessage: String?
    @Published var preferredWage: Int {
        didSet { defaults.set(preferredWage, forKey: "hourly_wage"); refreshSnapshot() }
    }
    @Published var interval: ReminderInterval {
        didSet { defaults.set(interval.rawValue, forKey: "reminder_interval"); updateReminders() }
    }
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: "reminders_enabled"); updateReminders() }
    }

    let economy: EconomyStore
    private let context: ModelContext
    private let scheduler: any SessionReminding
    private let defaults: UserDefaults
    private let now: () -> Date
    private let continuousNow: () -> TimeInterval
    private let bootSessionID: () -> String
    private let beforeReset: () throws -> Void
    weak var syncDelegate: SessionSyncing?

    init(context: ModelContext, economy: EconomyStore, scheduler: any SessionReminding,
         defaults: UserDefaults = AppConfig.shared ?? .standard, now: @escaping () -> Date = Date.init,
         continuousNow: @escaping () -> TimeInterval = RewardClock.now,
         bootSessionID: @escaping () -> String = { RewardClock.bootSessionID },
         beforeReset: @escaping () throws -> Void = {}) {
        self.context = context
        self.economy = economy
        self.scheduler = scheduler
        self.defaults = defaults
        self.now = now
        self.continuousNow = continuousNow
        self.bootSessionID = bootSessionID
        self.beforeReset = beforeReset
        let wage = defaults.integer(forKey: "hourly_wage")
        self.preferredWage = (1...EarningsCalculator.maximumWage).contains(wage) ? wage : 10_000
        self.interval = ReminderInterval(rawValue: defaults.integer(forKey: "reminder_interval")) ?? .m60
        self.notificationsEnabled = defaults.bool(forKey: "reminders_enabled")
    }

    /// UI actions surface a save failure and keep the last committed state intact.
    @discardableResult
    func perform(_ action: () throws -> Void) -> Bool {
        do { try action(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }

    func start(wage: Int? = nil) throws {
        // An in-memory controller is not the authority: another scene may already
        // have started work before this controller received its first snapshot.
        if try !activeSessions().isEmpty {
            try recoverIfNeeded()
            return
        }
        current = nil
        let wage = wage ?? preferredWage
        guard (1...EarningsCalculator.maximumWage).contains(wage) else { throw EconomyStore.StoreError.invalidRecord }
        let date = now()
        let session = WorkSession(startedAt: date, wage: wage)
        try economy.transaction {
            let tick = continuousNow()
            let boot = bootSessionID()
            let rewardDate = try economy.rewardDate(now: date, tick: tick, bootSessionID: boot)
            var tracking = RewardTracking(date: rewardDate, tick: tick, working: true, bootSessionID: boot)
            tracking.wageClockAnchor = RewardClockAnchor(date: date, tick: tick, bootSessionID: boot)
            try session.setRewardTracking(tracking)
            context.insert(session)
        }
        current = session
        defaults.set(session.id, forKey: AppConfig.kActiveSession)
        refreshSnapshot()
        updateReminders()
    }

    func pause() throws {
        guard let session = current, session.isActive, session.currentWage > 0 else { return }
        try appendSegment(wage: 0, to: session)
    }

    func resume() throws {
        guard let session = current, session.isActive, session.currentWage == 0 else { return }
        guard let wage = try session.decodedSegments().last(where: { $0.hourlyWage > 0 })?.hourlyWage else {
            throw EconomyStore.StoreError.corruptRecord
        }
        try appendSegment(wage: wage, to: session)
    }

    private func appendSegment(wage: Int, to session: WorkSession) throws {
        let date = now()
        try economy.transaction(restoring: session.restorePoint()) {
            try checkpoint(session, date: date, working: wage > 0)
            var segments = try session.decodedSegments()
            guard let index = segments.indices.last else { throw EconomyStore.StoreError.corruptRecord }
            let boundary = max(date, segments[index].start)
            segments[index].end = boundary
            segments.append(.init(start: boundary, hourlyWage: wage))
            session.segments = segments
        }
        refreshSnapshot()
        updateReminders()
    }

    @discardableResult
    func stop() throws -> Int {
        guard let session = current else { return 0 }
        guard session.isActive else {
            current = nil
            refreshSnapshot()
            updateReminders()
            return 0
        }
        let date = now()
        var awarded = 0
        try economy.transaction(restoring: session.restorePoint()) {
            try checkpoint(session, date: date, working: false)
            var segments = try session.decodedSegments()
            guard let index = segments.indices.last else { throw EconomyStore.StoreError.corruptRecord }
            let boundary = max(date, segments[index].start)
            segments[index].end = boundary
            session.segments = segments
            session.endedAt = boundary
            session.isActive = false
            awarded = try economy.insertAccruals(for: session, now: date)
        }
        current = nil
        defaults.removeObject(forKey: AppConfig.kActiveSession)
        refreshSnapshot()
        updateReminders()
        return awarded
    }

    private func checkpoint(_ session: WorkSession, date: Date, working: Bool) throws {
        let tick = continuousNow()
        let boot = bootSessionID()
        let rewardDate = try economy.rewardDate(now: date, tick: tick, bootSessionID: boot)
        var tracking = try session.rewardTracking() ?? RewardTracking(date: rewardDate, tick: tick, working: working, bootSessionID: boot)
        try reconcileWageClock(session, anchor: tracking.wageClockAnchor, date: date, tick: tick, boot: boot)
        tracking.wageClockAnchor = RewardClockAnchor(date: date, tick: tick, bootSessionID: boot)
        tracking.checkpoint(date: rewardDate, tick: tick, working: working, bootSessionID: boot)
        try session.setRewardTracking(tracking)
    }

    /// Rebase only the active record after a wall-clock correction. Relative work
    /// and pause durations survive; finalized records and reward dates never move.
    private func reconcileWageClock(_ session: WorkSession, anchor: RewardClockAnchor?,
                                    date: Date, tick: TimeInterval, boot: String) throws {
        var segments = try session.decodedSegments()
        guard let last = segments.last else { throw EconomyStore.StoreError.corruptRecord }
        let measured = anchor.map { tick - $0.tick }
        let sameBoot = anchor?.bootSessionID == boot && measured?.isFinite == true && measured! >= 0
        let projected = max(last.start, anchor.map {
            sameBoot ? $0.date.addingTimeInterval(measured!) : $0.date
        } ?? last.start)
        // No reliable elapsed time exists across a reboot; only rebase backwards
        // when necessary, retaining time already checkpointed before that reboot.
        guard date < last.start || (sameBoot && abs(projected.timeIntervalSince(date)) > 1)
                || (!sameBoot && date < projected) else { return }
        // Integer-millisecond translation preserves the calculator's rounding of
        // both endpoints, even for fractional-second segments and maximum wages.
        let shiftMilliseconds = (date.timeIntervalSince1970 * 1000).rounded()
            - (projected.timeIntervalSince1970 * 1000).rounded()
        func translated(_ value: Date) -> Date {
            // Canonicalize each endpoint first: adding an offset to a half-ms
            // floating-point value can otherwise flip its rounding by one ms.
            Date(timeIntervalSince1970: ((value.timeIntervalSince1970 * 1000).rounded() + shiftMilliseconds) / 1000)
        }
        for index in segments.indices {
            segments[index].start = translated(segments[index].start)
            if let end = segments[index].end { segments[index].end = translated(end) }
        }
        session.startedAt = translated(session.startedAt)
        session.segments = segments
    }

    /// Event-driven persistence retains measured time across app termination without
    /// running an extra timer, a background task, or keeping the device awake.
    func checkpointRewards() throws {
        guard let session = current, session.isActive else { return }
        try economy.transaction(restoring: session.restorePoint()) {
            try checkpoint(session, date: now(), working: session.currentWage > 0)
        }
    }

    func recoverIfNeeded() throws {
        // SwiftData is authoritative. UserDefaults can be lost between save and snapshot.
        let active = try activeSessions()
        if !active.isEmpty {
            let date = now()
            let restores = active.map { $0.restorePoint() }
            var ordered = active
            try economy.transaction(restoring: { restores.forEach { $0() } }) {
                // Keep the latest session running; preserve older records, closing
                // their open interval where the next session began. Settlement
                // unions timer proof, so overlapping records cannot duplicate points.
                for record in active {
                    try checkpoint(record, date: date, working: record.currentWage > 0)
                }
                // A clock correction can reverse the original civil-time order.
                // Select the latest record only after every timeline is rebased.
                ordered.sort { $0.startedAt == $1.startedAt ? $0.id < $1.id : $0.startedAt < $1.startedAt }
                for (index, record) in ordered.dropLast().enumerated() {
                    var segments = try record.decodedSegments()
                    guard let last = segments.indices.last else { throw EconomyStore.StoreError.corruptRecord }
                    let end = max(segments[last].start, min(date, ordered[index + 1].startedAt))
                    segments[last].end = end
                    record.segments = segments
                    record.endedAt = end
                    record.isActive = false
                    if var tracking = try record.rewardTracking() {
                        tracking.working = false
                        try record.setRewardTracking(tracking)
                    }
                    try economy.insertAccruals(for: record, now: date)
                }
            }
            let session = ordered[ordered.count - 1]
            current = session
            defaults.set(session.id, forKey: AppConfig.kActiveSession)
            if active.count > 1 {
                recoveryMessage = "여러 창에서 시작된 근무를 정리했어요. 가장 최근 근무를 이어가며 이전 기록은 보관했어요. 기록 탭에서 시간을 확인해 주세요."
            }
        } else {
            current = nil
            defaults.removeObject(forKey: AppConfig.kActiveSession)
        }
        refreshSnapshot()
        updateReminders()
    }

    private func activeSessions() throws -> [WorkSession] {
        try context.fetch(FetchDescriptor<WorkSession>(predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.startedAt), SortDescriptor(\.id)]))
    }

    /// Used by both foreground entry and Watch requests, including after the
    /// operating system has delivered every notification in the previous window.
    func refresh() {
        perform { try recoverIfNeeded() }
    }

    func handleRemoteCommand(_ command: WatchCommand) throws {
        let age = now().timeIntervalSince(command.createdAt)
        guard (-5...30).contains(age) else { throw RemoteError.expired }
        let ids = defaults.stringArray(forKey: "watch_command_ids") ?? []
        if ids.contains(command.id) { return }
        guard command.sessionId == current?.id else { throw RemoteError.changed }
        switch command.action {
        case "start": try start()
        case "stop": try stop()
        case "pause": try pause()
        case "resume": try resume()
        default: throw RemoteError.changed
        }
        defaults.set(Array((ids + [command.id]).suffix(30)), forKey: "watch_command_ids")
    }

    enum RemoteError: LocalizedError {
        case expired, changed
        var errorDescription: String? {
            switch self {
            case .expired: "요청 시간이 지났어요. 상태를 새로고침한 뒤 다시 눌러 주세요."
            case .changed: "iPhone에서 근무 상태가 바뀌었어요. 다시 확인해 주세요."
            }
        }
    }

    func refreshSnapshot() {
        do {
            let date = now()
            let segments = try current?.decodedSegments()
            let completed = try economy.completedEarningsSnapshot(at: date)
            snapshot = SessionSnapshot(isRunning: current?.isActive ?? false,
                isPaused: current != nil && current?.currentWage == 0, sessionId: current?.id,
                startedAt: current?.startedAt, accrued: current?.accrued(until: date) ?? 0,
                wage: current?.currentWage ?? 0, segments: segments, capturedAt: date,
                completedToday: completed.amount(on: date), preferredWage: preferredWage, completedEarnings: completed)
            defaults.set(try JSONEncoder().encode(snapshot), forKey: AppConfig.kSnapshot)
            syncDelegate?.didUpdateSession(snapshot)
            #if os(iOS)
            WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.widgetKind)
            #endif
        } catch { errorMessage = error.localizedDescription }
    }

    func resetAll() throws {
        // Do not report a complete reset while a pre-migration copy still holds
        // the person's records. A cleanup failure leaves the active store intact.
        try beforeReset()
        try economy.resetAll()
        current = nil
        defaults.removeObject(forKey: AppConfig.kActiveSession)
        defaults.removeObject(forKey: "watch_command_ids")
        refreshSnapshot()
        updateReminders()
        NotificationCenter.default.post(name: .piyakEquippedChanged, object: nil)
    }

    func updateReminders() {
        scheduler.update(snapshot: snapshot, interval: interval, enabled: notificationsEnabled)
    }
}
