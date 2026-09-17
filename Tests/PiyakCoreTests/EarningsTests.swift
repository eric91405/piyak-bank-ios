import Foundation
import Testing
@testable import PiyakCore

private func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

@Test func exactHourAndPause() {
    let start = utc("2026-09-17T09:00:00Z")
    let segments = [
        WageSegment(start: start, end: start.addingTimeInterval(3600), hourlyWage: 10_000),
        WageSegment(start: start.addingTimeInterval(3600), end: start.addingTimeInterval(7200), hourlyWage: 0),
        WageSegment(start: start.addingTimeInterval(7200), hourlyWage: 10_000)
    ]
    let now = start.addingTimeInterval(9000)
    #expect(EarningsCalculator.total(Array(segments.prefix(1)), until: now) == 10_000)
    #expect(EarningsCalculator.total(segments, until: now) == 15_000)
    #expect(EarningsCalculator.workingSeconds(segments, until: now) == 5400)
    let snapshot = SessionSnapshot(isRunning: true, isPaused: false, accrued: 0, wage: 10_000, segments: segments)
    #expect(snapshot.amount(at: now) == 15_000)
}

@Test func midnightConservesRounding() {
    let start = utc("2026-09-16T23:59:59Z")
    let end = start.addingTimeInterval(2)
    let segments = [WageSegment(start: start, end: end, hourlyWage: 10_000)]
    let days = EarningsCalculator.daily(segments, until: end, calendar: calendar)
    #expect(days.map(\.amount) == [2, 3])
    #expect(days.reduce(0) { $0 + $1.amount } == EarningsCalculator.total(segments, until: end))
}

@Test func overnightAndStaleSnapshot() {
    let start = utc("2026-09-16T23:00:00Z")
    let now = utc("2026-09-17T01:00:00Z")
    let segments = [WageSegment(start: start, hourlyWage: 10_000)]
    let snapshot = SessionSnapshot(isRunning: true, isPaused: false, accrued: 0, wage: 10_000,
                                  segments: segments, capturedAt: start, completedToday: 90_000)
    #expect(snapshot.amount(at: now) == 20_000)
    #expect(snapshot.today(at: now, calendar: calendar) == 10_000)
}

@Test func fractionsCarryAcrossSegments() {
    let start = utc("2026-09-17T00:00:00Z")
    let segments = (0..<3600).map {
        WageSegment(start: start.addingTimeInterval(Double($0)), end: start.addingTimeInterval(Double($0 + 1)), hourlyWage: 10_000)
    }
    #expect(EarningsCalculator.total(segments, until: start.addingTimeInterval(3600)) == 10_000)
}

@Test func futureAndReversedTimeDoesNotEarn() {
    let now = Date()
    #expect(EarningsCalculator.total([.init(start: now.addingTimeInterval(10), hourlyWage: 10_000)], until: now) == 0)
    #expect(EarningsCalculator.total([.init(start: now, end: now.addingTimeInterval(-1), hourlyWage: 10_000)], until: now) == 0)
}

@Test func daylightSavingBoundary() {
    var cal = calendar
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    let start = utc("2026-03-08T05:00:00Z")
    let end = utc("2026-03-09T04:00:00Z")
    let segments = [WageSegment(start: start, end: end, hourlyWage: 10_000)]
    let days = EarningsCalculator.daily(segments, until: end, calendar: cal)
    #expect(days.count == 1)
    #expect(days.first?.amount == 230_000)
}

@Test func oldSnapshotStillDecodes() throws {
    let data = Data(#"{"isRunning":false,"isPaused":false,"accrued":150,"wage":0}"#.utf8)
    let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: data)
    #expect(snapshot.amount() == 150)
}

@Test func splitConservesFractionalMilliseconds() {
    let midnight = utc("2026-09-17T00:00:00Z")
    for i in 0..<1000 {
        let start = midnight.addingTimeInterval(-1.0 - Double(i) / 1234)
        let end = midnight.addingTimeInterval(1.0 + Double(i) / 1367)
        let segments = [WageSegment(start: start, end: end, hourlyWage: 999_983)]
        #expect(EarningsCalculator.daily(segments, until: end, calendar: calendar).reduce(0) { $0 + $1.amount }
                == EarningsCalculator.total(segments, until: end))
    }
}
