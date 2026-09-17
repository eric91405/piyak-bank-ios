import Foundation

enum AppConfig {
    static let appGroup = "group.com.minseo.piyakbank"
    static var shared: UserDefaults? { UserDefaults(suiteName: appGroup) }
    static let kSnapshot = "session_snapshot"
    static let kActiveSession = "active_session_id"
    static let supportEmail = "eric91405@gmail.com"
    static let operatorName = "김민서"
    static let widgetKind = "PiyakComplication"
}

/// Optional additions preserve decoding of snapshots from earlier app versions.
struct SessionSnapshot: Codable, Hashable, Sendable {
    var isRunning: Bool
    var isPaused: Bool
    var sessionId: String?
    var startedAt: Date?
    var accrued: Int
    var wage: Int
    var segments: [WageSegment]?
    var capturedAt: Date?
    var completedToday: Int?
    var preferredWage: Int?

    static let empty = SessionSnapshot(isRunning: false, isPaused: false, accrued: 0, wage: 0)

    func amount(at date: Date = .now) -> Int {
        guard let segments else { return accrued }
        return EarningsCalculator.total(segments, until: date)
    }

    func today(at date: Date = .now, calendar: Calendar = .current) -> Int {
        let settled = capturedAt.map { calendar.isDate($0, inSameDayAs: date) } == true
            ? (completedToday ?? 0) : 0
        return settled + EarningsCalculator.earned(on: date, segments: segments ?? [], until: date, calendar: calendar)
    }
}

struct WatchCommand: Codable, Sendable {
    var id = UUID().uuidString
    var action: String
    var sessionId: String?
    var createdAt = Date()
}

func floorToInt(_ d: Decimal) -> Int {
    var v = d
    var r = Decimal()
    NSDecimalRound(&r, &v, 0, .down)
    return (r as NSDecimalNumber).intValue
}

extension Int {
    var grouped: String { formatted(.number.locale(Locale(identifier: "ko_KR"))) }
    var won: String { grouped + "원" }
    var points: String { grouped + " P" }
}
