import Foundation
import SwiftData
import Combine

/// 워치/위젯이 읽을 경량 세션 상태 (AppGroup 공유)
protocol SessionSyncing: AnyObject {
    func didUpdateSession(_ snapshot: SessionSnapshot)
}

struct SessionSnapshot: Codable, Hashable {
    var isRunning: Bool
    var isPaused: Bool
    var sessionId: String?
    var startedAt: Date?
    var accrued: Int
    var wage: Int
}

@MainActor
final class SessionController: ObservableObject {

    @Published private(set) var current: WorkSession?
    @Published private(set) var snapshot = SessionSnapshot(
        isRunning: false, isPaused: false, sessionId: nil,
        startedAt: nil, accrued: 0, wage: 0)

    private let context: ModelContext
    private let economy: EconomyStore
    private let scheduler: NotificationScheduler
    weak var syncDelegate: SessionSyncing?

    private let interval: NotificationScheduler.Interval = .m60   // 기본 60분

    /// AppGroup 공유 저장소 (강제종료 복구 + 위젯)
    private let defaults = UserDefaults(suiteName: "group.com.minseo.piyakbank")
    private let activeKey = "active_session_id"

    init(context: ModelContext, economy: EconomyStore, scheduler: NotificationScheduler) {
        self.context = context
        self.economy = economy
        self.scheduler = scheduler
    }

    // MARK: 시작

    func start(wage: Int, plannedEnd: Date? = nil) {
        guard current == nil else { return }
        let s = WorkSession(wage: wage)
        context.insert(s)
        try? context.save()
        current = s
        defaults?.set(s.id, forKey: activeKey)

        let baseline = economy.dailyAccrued(on: .now)
        scheduler.schedule(session: s, interval: interval,
                           plannedEnd: plannedEnd, dailyBaseline: baseline)
        pushSnapshot()
    }

    // MARK: 일시정지 / 재개 (시급 0 구간으로 표현)

    func pause() {
        guard let s = current, s.isActive else { return }
        var segs = s.segments
        if let last = segs.indices.last, segs[last].end == nil {
            segs[last].end = .now
        }
        segs.append(WageSegment(start: .now, end: nil, hourlyWage: 0)) // 정지 구간
        s.segments = segs
        try? context.save()
        scheduler.cancel(sessionId: s.id)
        pushSnapshot()
    }

    func resume() {
        guard let s = current, s.isActive else { return }
        var segs = s.segments
        let lastWage = segs.dropLast().last(where: { $0.hourlyWage > 0 })?.hourlyWage ?? 0
        if let last = segs.indices.last, segs[last].end == nil {
            segs[last].end = .now   // 정지 구간 닫기
        }
        segs.append(WageSegment(start: .now, end: nil, hourlyWage: lastWage))
        s.segments = segs
        try? context.save()
        let baseline = economy.dailyAccrued(on: .now)
        scheduler.schedule(session: s, interval: interval,
                           plannedEnd: nil, dailyBaseline: baseline)
        pushSnapshot()
    }

    // MARK: 정지 (정산)

    func stop() {
        guard let s = current else { return }
        let now = Date()
        var segs = s.segments
        if let last = segs.indices.last, segs[last].end == nil {
            segs[last].end = now
        }
        s.segments = segs
        s.endedAt = now
        s.isActive = false

        // 자정 분할 정산: 구간을 날짜별로 쪼개 원장에 적립
        recordAccrualSplitByMidnight(session: s)

        scheduler.cancel(sessionId: s.id)
        try? context.save()
        defaults?.removeObject(forKey: activeKey)
        current = nil
        pushSnapshot()
    }

    /// 날짜 경계로 적립액을 분할해 PointTransaction 기록 (자정 리셋 없이 날짜 귀속만 분리)
    private func recordAccrualSplitByMidnight(session s: WorkSession) {
        let cal = Calendar.current
        for seg in s.segments where seg.hourlyWage > 0 {
            guard let segEnd = seg.end else { continue }
            var cursor = seg.start
            while cursor < segEnd {
                let dayStart = cal.startOfDay(for: cursor)
                let nextMidnight = cal.date(byAdding: .day, value: 1, to: dayStart)!
                let sliceEnd = min(segEnd, nextMidnight)
                let piece = WageSegment(start: cursor, end: sliceEnd, hourlyWage: seg.hourlyWage)
                economy.recordAccrual(piece.accrued(), sessionId: s.id, at: cursor)
                cursor = sliceEnd
            }
        }
    }

    // MARK: 강제종료 복구

    func recoverIfNeeded() {
        guard current == nil, let sid = defaults?.string(forKey: activeKey) else { return }
        let desc = FetchDescriptor<WorkSession>(predicate: #Predicate { $0.id == sid })
        guard let s = try? context.fetch(desc).first, s.isActive else {
            defaults?.removeObject(forKey: activeKey); return
        }
        current = s
        let baseline = economy.dailyAccrued(on: .now)
        scheduler.schedule(session: s, interval: interval,
                           plannedEnd: nil, dailyBaseline: baseline)
        pushSnapshot()
    }

    // MARK: 워치 원격 제어 진입점

    func handleRemoteCommand(_ command: String, wage: Int?) {
        switch command {
        case "start": if let w = wage { start(wage: w) }
        case "stop":  stop()
        case "pause": pause()
        case "resume": resume()
        default: break
        }
    }

    // MARK: 스냅샷 갱신 (UI 타이머에서 주기 호출)

    func refreshSnapshot() { pushSnapshot() }

    private func pushSnapshot() {
        let snap = SessionSnapshot(
            isRunning: current?.isActive ?? false,
            isPaused: current?.currentWage == 0 && (current?.isActive ?? false),
            sessionId: current?.id,
            startedAt: current?.startedAt,
            accrued: current?.accrued() ?? 0,
            wage: current?.currentWage ?? 0)
        snapshot = snap
        if let data = try? JSONEncoder().encode(snap) {
            defaults?.set(data, forKey: "session_snapshot")
        }
        syncDelegate?.didUpdateSession(snap)
    }
}
