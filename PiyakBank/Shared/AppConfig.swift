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
