import Foundation

/// 3타깃(iOS/Watch/Widget) 공유 설정.
enum AppConfig {
    /// App Group 컨테이너 ID — Signing & Capabilities에서 동일하게 등록할 것
    static let appGroup = "group.com.minseo.piyakbank"

    /// 공유 UserDefaults (세션 스냅샷 · 강제종료 복구)
    static var shared: UserDefaults? { UserDefaults(suiteName: appGroup) }

    // 공유 키
    static let kSnapshot = "session_snapshot"
    static let kActiveSession = "active_session_id"
}

// MARK: - 세션 스냅샷 (iOS/Watch/Widget 공유)
struct SessionSnapshot: Codable, Hashable {
    var isRunning: Bool
    var isPaused: Bool
    var sessionId: String?
    var startedAt: Date?
    var accrued: Int
    var wage: Int
}

// MARK: - 공유 헬퍼 (iOS/Watch/Widget)

func floorToInt(_ d: Decimal) -> Int {
    var v = d
    var r = Decimal()
    NSDecimalRound(&r, &v, 0, .down)
    return (r as NSDecimalNumber).intValue
}

extension Int {
    var won: String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return (f.string(from: NSNumber(value: self)) ?? "\(self)") + "원"
    }
}
