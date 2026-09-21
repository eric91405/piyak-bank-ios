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
    var completedEarnings: CompletedEarningsSnapshot?

    static let empty = SessionSnapshot(isRunning: false, isPaused: false, accrued: 0, wage: 0)

    func amount(at date: Date = .now) -> Int {
        guard let segments else { return accrued }
        return EarningsCalculator.total(segments, until: date)
    }

    func today(at date: Date = .now, calendar: Calendar = .current) -> Int {
        // Older aggregates have no source timezone. Do not label that unknown
        // amount as today's pay after travel; the next phone refresh replaces it.
        let settled = completedEarnings?.amount(on: date, calendar: calendar) ?? 0
        return settled + EarningsCalculator.earned(on: date, segments: segments ?? [], until: date, calendar: calendar)
    }
}

/// A bounded table of local-day totals, rather than a copy of the user's history.
/// Timezones sharing a midnight share one entry. Computing the boundaries at
/// capture time also accounts for daylight-saving transitions and calendar choice.
struct CompletedEarningsSnapshot: Codable, Hashable, Sendable {
    struct Day: Codable, Hashable, Sendable {
        var start: Date
        var amount: Int
    }

    private(set) var days: [Day]

    init(at date: Date, calendar: Calendar = .current) {
        var localCalendar = calendar
        var starts: Set<Date> = [calendar.startOfDay(for: date)]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            guard let timezone = TimeZone(identifier: identifier) else { continue }
            localCalendar.timeZone = timezone
            starts.insert(localCalendar.startOfDay(for: date))
        }
        days = starts.sorted().map { Day(start: $0, amount: 0) }
    }

    var earliestDayStart: Date? { days.first?.start }

    mutating func add(_ segments: [WageSegment], until date: Date) {
        let total = EarningsCalculator.total(segments, until: date)
        for index in days.indices {
            // Round each record's cumulative amount on either side of midnight.
            // Clipping segments first or combining records loses fractional won.
            days[index].amount += total - EarningsCalculator.total(segments, until: days[index].start)
        }
    }

    func amount(on date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        return days.first { $0.start == start }?.amount ?? 0
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
