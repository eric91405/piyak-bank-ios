import Foundation

/// Immutable receipts store measured working time separately from editable pay records.
public struct RewardInterval: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

public struct RewardDay: Equatable, Sendable {
    public let day: Date
    /// Eligible, non-overlapping working time after this day's eight-hour cap.
    public let creditedMilliseconds: Int64
    public let points: Int
}

/// Wages never enter this calculation. Callers supply only timer-measured intervals.
public enum RewardPolicy {
    public static let millisecondsPerPoint: Int64 = 6_000
    public static let dailyPointLimit = 4_800
    public static let pointsPerDay = dailyPointLimit
    public static let pointsPerLevel = 4_800
    public static let dailyMillisecondsLimit: Int64 = 28_800_000
    /// A device time-zone change must not reopen the same day's earning allowance.
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    // Persisted input can be corrupt. A single receipt cannot require an unbounded
    // calendar walk; normal timer intervals are much shorter than this limit.
    private static let maximumIntervalDuration: TimeInterval = 31 * 24 * 60 * 60

    private struct MillisecondInterval {
        var start: Int64
        var end: Int64
    }

    /// Union all receipts before awarding points: retries, duplicates and overlapping
    /// sessions cannot award the same instant twice. Fractional points carry between
    /// sessions within a day, but do not bypass a day's cap at midnight.
    ///
    /// The caller must use the same calendar for the entire receipt history, including
    /// when the device's time zone changes. Invalid intervals are ignored.
    public static func daily(_ intervals: [RewardInterval], calendar: Calendar) -> [RewardDay] {
        let sorted = intervals.compactMap(validMilliseconds).sorted {
            $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start
        }
        var united: [MillisecondInterval] = []
        for interval in sorted {
            if let last = united.last, interval.start <= last.end {
                united[united.count - 1].end = max(last.end, interval.end)
            } else {
                united.append(interval)
            }
        }

        var millisecondsByDay: [Date: Int64] = [:]
        for interval in united {
            var cursor = interval.start
            while cursor < interval.end {
                let date = Date(timeIntervalSince1970: Double(cursor) / 1_000)
                let day = calendar.startOfDay(for: date)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day),
                      let nextDayMilliseconds = timestamp(nextDay),
                      nextDayMilliseconds > cursor else { break }
                let stop = min(interval.end, nextDayMilliseconds)
                let prior = millisecondsByDay[day, default: 0]
                millisecondsByDay[day] = min(dailyMillisecondsLimit, prior + stop - cursor)
                cursor = stop
            }
        }

        return millisecondsByDay.map { day, milliseconds in
            RewardDay(day: day, creditedMilliseconds: milliseconds,
                      points: Int(milliseconds / millisecondsPerPoint))
        }.sorted { $0.day < $1.day }
    }

    public static func total(_ intervals: [RewardInterval], calendar: Calendar) -> Int {
        daily(intervals, calendar: calendar).reduce(0) { $0 + $1.points }
    }

    private static func validMilliseconds(_ interval: RewardInterval) -> MillisecondInterval? {
        let duration = interval.end.timeIntervalSince(interval.start)
        guard duration.isFinite, duration > 0, duration <= maximumIntervalDuration,
              let start = timestamp(interval.start), let end = timestamp(interval.end),
              end > start else { return nil }
        return MillisecondInterval(start: start, end: end)
    }

    private static func timestamp(_ date: Date) -> Int64? {
        let seconds = date.timeIntervalSince1970
        // Keep Foundation calendar arithmetic in its supported civil-date range and
        // guard the floating-point-to-integer conversion against NaN and infinity.
        guard seconds.isFinite, date >= .distantPast, date <= .distantFuture else { return nil }
        return Int64((seconds * 1_000).rounded(.down))
    }
}
