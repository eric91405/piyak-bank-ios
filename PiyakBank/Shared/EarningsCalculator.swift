import Foundation

struct WageSegment: Codable, Hashable, Sendable {
    var start: Date
    var end: Date?
    var hourlyWage: Int

    func accrued(until now: Date = .now) -> Int {
        EarningsCalculator.total([self], until: now)
    }
}

enum EarningsCalculator {
    static let maximumWage = 1_000_000
    static let maximumSessionDuration: TimeInterval = 7 * 24 * 60 * 60

    struct DayAmount: Equatable, Sendable {
        var day: Date
        var amount: Int
    }

    private static func numerator(_ segment: WageSegment, from: Date, to: Date) -> Decimal {
        guard to > from, segment.hourlyWage > 0 else { return 0 }
        let milliseconds = max(0, (to.timeIntervalSince1970 * 1000).rounded() - (from.timeIntervalSince1970 * 1000).rounded())
        return Decimal(milliseconds) * Decimal(segment.hourlyWage)
    }

    /// Multiply first, divide once: wage / 3600 has repeating-decimal rounding errors.
    static func total(_ segments: [WageSegment], until now: Date = .now) -> Int {
        let sum = segments.reduce(Decimal.zero) { result, segment in
            result + numerator(segment, from: segment.start, to: min(segment.end ?? now, now))
        }
        return floorToInt(sum / 3_600_000)
    }

    /// Carry fractional won across pauses and midnight; daily entries sum to the total.
    static func daily(_ segments: [WageSegment], until now: Date = .now,
                      calendar: Calendar = .current) -> [DayAmount] {
        var result: [Date: Int] = [:]
        var sum = Decimal.zero
        var allocated = 0
        for segment in segments.sorted(by: { $0.start < $1.start }) where segment.hourlyWage > 0 {
            let end = min(segment.end ?? now, now)
            var cursor = segment.start
            while cursor < end {
                let day = calendar.startOfDay(for: cursor)
                guard let midnight = calendar.date(byAdding: .day, value: 1, to: day), midnight > cursor else { break }
                let stop = min(end, midnight)
                sum += numerator(segment, from: cursor, to: stop)
                let rounded = floorToInt(sum / 3_600_000)
                result[day, default: 0] += rounded - allocated
                allocated = rounded
                cursor = stop
            }
        }
        return result.map { DayAmount(day: $0.key, amount: $0.value) }.sorted { $0.day < $1.day }
    }

    static func earned(on day: Date, segments: [WageSegment], until now: Date = .now,
                       calendar: Calendar = .current) -> Int {
        daily(segments, until: now, calendar: calendar)
            .first { calendar.isDate($0.day, inSameDayAs: day) }?.amount ?? 0
    }

    static func workingSeconds(_ segments: [WageSegment], until now: Date = .now) -> TimeInterval {
        segments.filter { $0.hourlyWage > 0 }.reduce(0) {
            $0 + max(0, min($1.end ?? now, now).timeIntervalSince($1.start))
        }
    }
}
