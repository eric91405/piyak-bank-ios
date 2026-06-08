import Foundation
import SwiftData
import UserNotifications

// MARK: - 시급 구간 (세션 내 시급 변경/일시정지를 구간으로 표현)
// 세션 중 시급 변경은 UI에서 차단하지만, 일시정지=시급0 구간 처리를 위해 구조는 유지.

struct WageSegment: Codable, Hashable {
    var start: Date
    var end: Date?          // nil이면 진행 중
    var hourlyWage: Int     // 시급(원). 일시정지 구간은 0

    func accrued(until now: Date = .now) -> Int {
        let stop = end ?? now
        guard stop > start, hourlyWage > 0 else { return 0 }
        let seconds = Decimal(stop.timeIntervalSince(start))
        let perSecond = Decimal(hourlyWage) / 3600
        let raw = perSecond * seconds
        return floorToInt(raw)   // floor 통일
    }
}

func floorToInt(_ d: Decimal) -> Int {
    var v = d
    var r = Decimal()
    NSDecimalRound(&r, &v, 0, .down)
    return (r as NSDecimalNumber).intValue
}

// MARK: - 근무 세션

@Model
final class WorkSession {
    @Attribute(.unique) var id: String     // 식별자 base (piyak.{id}....)
    var startedAt: Date
    var endedAt: Date?
    /// 구간 직렬화 (SwiftData가 struct 배열을 직접 못 다루므로 Data로 보관)
    var segmentsData: Data
    var isActive: Bool

    var segments: [WageSegment] {
        get { (try? JSONDecoder().decode([WageSegment].self, from: segmentsData)) ?? [] }
        set { segmentsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(id: String = UUID().uuidString, startedAt: Date = .now, wage: Int) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = nil
        self.isActive = true
        self.segmentsData = (try? JSONEncoder().encode([WageSegment(start: startedAt, end: nil, hourlyWage: wage)])) ?? Data()
    }

    /// 현재 시각 기준 누적 적립
    func accrued(until now: Date = .now) -> Int {
        segments.reduce(0) { $0 + $1.accrued(until: now) }
    }

    /// 현재 적용 시급 (마지막 구간)
    var currentWage: Int { segments.last?.hourlyWage ?? 0 }
}

// MARK: - 알림 스케줄러
// 주기 알림(periodic) + 마일스톤 알림(milestone)을 사전 예약.
// 식별자: piyak.{sid}.{type}.{key}
// 예약 윈도우: min(종료예정, 48 × 간격). expectedAmount는 예약 시점 값으로 고정.

@MainActor
final class NotificationScheduler {

    enum Interval: Int, CaseIterable { case m15 = 15, m30 = 30, m60 = 60 }

    static let maxPeriodic = 48
    static let maxMilestone = 12
    /// 일일 누적 금액 사다리 (원)
    static let milestoneLadder = [10_000, 30_000, 50_000, 100_000, 150_000, 200_000]

    let center = UNUserNotificationCenter.current()

    func requestAuth() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// 세션 시작/재개 시 호출. 기존 예약을 지우고 다시 깐다.
    func schedule(session: WorkSession,
                  interval: Interval,
                  plannedEnd: Date?,
                  dailyBaseline: Int) {
        cancel(sessionId: session.id)
        let wage = session.currentWage
        guard wage > 0 else { return }

        let now = Date()
        let step = TimeInterval(interval.rawValue * 60)

        // 윈도우: min(종료예정, 48 × 간격)
        let windowEnd: Date = {
            let cap = now.addingTimeInterval(step * Double(Self.maxPeriodic))
            if let end = plannedEnd { return min(end, cap) }
            return cap
        }()

        var requests: [UNNotificationRequest] = []

        // 1) 주기 알림
        var fireAt = now.addingTimeInterval(step)
        var n = 0
        while fireAt <= windowEnd && n < Self.maxPeriodic {
            let elapsed = fireAt.timeIntervalSince(session.startedAt)
            let expected = floorToInt(Decimal(wage) / 3600 * Decimal(elapsed))
            requests.append(makeRequest(
                sid: session.id, type: "periodic", key: "\(n)",
                fireAt: fireAt,
                title: "삐약! 적립 중",
                body: "지금까지 \(expected.won) 모았어요 🐤"))
            fireAt = fireAt.addingTimeInterval(step)
            n += 1
        }

        // 2) 마일스톤 알림 (오늘 누적 baseline 기준 남은 사다리)
        var milestoneCount = 0
        for target in Self.milestoneLadder where target > dailyBaseline {
            if milestoneCount >= Self.maxMilestone { break }
            let remaining = target - dailyBaseline            // 이 세션에서 더 벌어야 할 액
            let secondsNeeded = Double(remaining) / (Double(wage) / 3600)
            let fire = session.startedAt.addingTimeInterval(secondsNeeded)
            guard fire > now, fire <= windowEnd else { continue }
            requests.append(makeRequest(
                sid: session.id, type: "milestone", key: "\(target)",
                fireAt: fire,
                title: "🎉 \(target.won) 달성!",
                body: "오늘 목표에 한 걸음 더!"))
            milestoneCount += 1
        }

        for r in requests { center.add(r) }
    }

    private func makeRequest(sid: String, type: String, key: String,
                             fireAt: Date, title: String, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // userInfo 스키마: 딥링크 + 적립 컨텍스트
        content.userInfo = [
            "sid": sid,
            "type": type,
            "key": key,
            "deeplink": "piyakbank://home"
        ]
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(
            identifier: "piyak.\(sid).\(type).\(key)",
            content: content, trigger: trigger)
    }

    /// 세션 종료/일시정지 시 해당 세션 예약 제거
    func cancel(sessionId: String) {
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map(\.identifier).filter { $0.hasPrefix("piyak.\(sessionId).") }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}

extension Int {
    /// 1,234원 포맷
    var won: String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return (f.string(from: NSNumber(value: self)) ?? "\(self)") + "원"
    }
}
