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
    weak var syncDelegate: SessionSyncing?

    init(context: ModelContext, economy: EconomyStore, scheduler: any SessionReminding,
         defaults: UserDefaults = AppConfig.shared ?? .standard, now: @escaping () -> Date = Date.init,
         continuousNow: @escaping () -> TimeInterval = RewardClock.now,
         bootSessionID: @escaping () -> String = { RewardClock.bootSessionID }) {
        self.context = context
        self.economy = economy
        self.scheduler = scheduler
        self.defaults = defaults
        self.now = now
        self.continuousNow = continuousNow
        self.bootSessionID = bootSessionID
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
        guard current == nil else { return }
        let wage = wage ?? preferredWage
        guard (1...EarningsCalculator.maximumWage).contains(wage) else { throw EconomyStore.StoreError.invalidRecord }
        let date = now()
        let session = WorkSession(startedAt: date, wage: wage)
        try economy.transaction {
            let tick = continuousNow()
            let boot = bootSessionID()
            let rewardDate = try economy.rewardDate(now: date, tick: tick, bootSessionID: boot)
            try session.setRewardTracking(RewardTracking(date: rewardDate, tick: tick, working: true, bootSessionID: boot))
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
        var segments = try session.decodedSegments()
        guard let index = segments.indices.last, segments[index].start <= date else { throw EconomyStore.StoreError.invalidRecord }
        segments[index].end = date
        segments.append(.init(start: date, hourlyWage: wage))
        try economy.transaction(restoring: session.restorePoint()) {
            try checkpoint(session, date: date, working: wage > 0)
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
        var segments = try session.decodedSegments()
        guard let index = segments.indices.last, segments[index].start <= date else { throw EconomyStore.StoreError.invalidRecord }
        segments[index].end = date
        var awarded = 0
        try economy.transaction(restoring: session.restorePoint()) {
            try checkpoint(session, date: date, working: false)
            session.segments = segments
            session.endedAt = date
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
        tracking.checkpoint(date: rewardDate, tick: tick, working: working, bootSessionID: boot)
        try session.setRewardTracking(tracking)
    }

    /// Event-driven persistence retains measured time across app termination without
    /// running an extra timer, a background task, or keeping the device awake.
    func checkpointRewards() throws {
        guard let session = current else { return }
        try economy.transaction(restoring: session.restorePoint()) {
            try checkpoint(session, date: now(), working: session.currentWage > 0)
        }
    }

    func recoverIfNeeded() throws {
        // SwiftData is authoritative. UserDefaults can be lost between save and snapshot.
        let active = try context.fetch(FetchDescriptor<WorkSession>(predicate: #Predicate { $0.isActive },
                                                                    sortBy: [SortDescriptor(\.startedAt)]))
        guard active.count <= 1 else { throw EconomyStore.StoreError.corruptRecord }
        if let session = active.first {
            let segments = try session.decodedSegments()
            guard !segments.isEmpty else { throw EconomyStore.StoreError.corruptRecord }
            current = session
            // An upgraded active session begins earning under the new policy now;
            // pre-upgrade editable segments cannot be used to manufacture rewards.
            try checkpointRewards()
            defaults.set(session.id, forKey: AppConfig.kActiveSession)
        } else {
            current = nil
            defaults.removeObject(forKey: AppConfig.kActiveSession)
        }
        refreshSnapshot()
        updateReminders()
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
            snapshot = SessionSnapshot(isRunning: current?.isActive ?? false,
                isPaused: current != nil && current?.currentWage == 0, sessionId: current?.id,
                startedAt: current?.startedAt, accrued: current?.accrued(until: date) ?? 0,
                wage: current?.currentWage ?? 0, segments: segments, capturedAt: date,
                completedToday: try economy.dailyAccrued(on: date, now: date), preferredWage: preferredWage)
            defaults.set(try JSONEncoder().encode(snapshot), forKey: AppConfig.kSnapshot)
            syncDelegate?.didUpdateSession(snapshot)
            #if os(iOS)
            WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.widgetKind)
            #endif
        } catch { errorMessage = error.localizedDescription }
    }

    func resetAll() throws {
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
