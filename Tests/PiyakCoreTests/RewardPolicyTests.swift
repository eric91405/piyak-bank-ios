import Foundation
import Testing
@testable import PiyakCore

private func rewardDate(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

private func rewardCalendar(_ zone: String = "UTC") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

private func rewardInterval(_ start: Date, seconds: TimeInterval) -> RewardInterval {
    RewardInterval(start: start, end: start.addingTimeInterval(seconds))
}

@Test func rewardsUseOnlyMeasuredTime() {
    let start = rewardDate("2026-09-17T09:00:00Z")
    let intervals = [rewardInterval(start, seconds: 600)]
    let days = RewardPolicy.daily(intervals, calendar: rewardCalendar())
    #expect(days.count == 1)
    #expect(days.first?.points == 100)
    #expect(days.first?.creditedMilliseconds == 600_000)
    #expect(RewardPolicy.total(intervals, calendar: rewardCalendar()) == 100)
    #expect(RewardPolicy.pointsPerLevel == 4_800)
}

@Test func rewardPausesEarnNothingAndPartialPointsCarryAcrossSessions() {
    let start = rewardDate("2026-09-17T09:00:00Z")
    let intervals = [
        rewardInterval(start, seconds: 2),
        rewardInterval(start.addingTimeInterval(600), seconds: 2),
        rewardInterval(start.addingTimeInterval(1_200), seconds: 2)
    ]
    #expect(RewardPolicy.total(intervals, calendar: rewardCalendar()) == 1)
    #expect(RewardPolicy.daily(intervals, calendar: rewardCalendar()).first?.creditedMilliseconds == 6_000)
    #expect(RewardPolicy.total(Array(intervals.prefix(2)), calendar: rewardCalendar()) == 0)
}

@Test func repeatedReceiptsAndOverlappingSessionsDoNotEarnTwice() {
    let start = rewardDate("2026-09-17T09:00:00Z")
    let first = rewardInterval(start, seconds: 600)
    let overlapping = rewardInterval(start.addingTimeInterval(300), seconds: 600)
    let contained = rewardInterval(start.addingTimeInterval(60), seconds: 60)
    let intervals = [overlapping, first, first, contained, overlapping]
    #expect(RewardPolicy.total(intervals, calendar: rewardCalendar()) == 150)
    #expect(RewardPolicy.total(Array(intervals.reversed()), calendar: rewardCalendar()) == 150)
    let before = RewardPolicy.total([first], calendar: rewardCalendar())
    let after = RewardPolicy.total([first, overlapping], calendar: rewardCalendar())
    #expect(after - before == 50)
    #expect(RewardPolicy.total(intervals + intervals, calendar: rewardCalendar()) == after)
}

@Test func rewardSplittingCannotCreateOrLosePoints() {
    let start = rewardDate("2026-09-17T09:00:00Z")
    let pieces = (0..<6_000).map {
        RewardInterval(start: start.addingTimeInterval(Double($0) / 1_000),
                       end: start.addingTimeInterval(Double($0 + 1) / 1_000))
    }
    #expect(RewardPolicy.total(pieces, calendar: rewardCalendar()) == 1)
    #expect(RewardPolicy.daily(pieces, calendar: rewardCalendar()) ==
            RewardPolicy.daily([rewardInterval(start, seconds: 6)], calendar: rewardCalendar()))
}

@Test func rewardDailyCapAppliesAcrossSessions() throws {
    let start = rewardDate("2026-09-17T00:00:00Z")
    let intervals = [
        rewardInterval(start, seconds: 4 * 3_600),
        rewardInterval(start.addingTimeInterval(5 * 3_600), seconds: 6 * 3_600)
    ]
    let days = RewardPolicy.daily(intervals, calendar: rewardCalendar())
    let day = try #require(days.first)
    #expect(day.points == 4_800)
    #expect(day.creditedMilliseconds == Int64(28_800_000))
    #expect(RewardPolicy.total(intervals + [rewardInterval(start, seconds: 23 * 3_600)],
                               calendar: rewardCalendar()) == 4_800)
}

@Test func rewardMidnightUsesInjectedCalendarAndResetsDailyCap() {
    let start = rewardDate("2026-09-17T14:59:54Z")
    let intervals = [rewardInterval(start, seconds: 12)]
    let days = RewardPolicy.daily(intervals, calendar: rewardCalendar("Asia/Seoul"))
    #expect(days.map(\.day) == [rewardDate("2026-09-16T15:00:00Z"), rewardDate("2026-09-17T15:00:00Z")])
    #expect(days.map(\.points) == [1, 1])
    #expect(days.map(\.creditedMilliseconds) == [6_000, 6_000])

    let long = [rewardInterval(rewardDate("2026-09-17T06:00:00Z"), seconds: 18 * 3_600)]
    #expect(RewardPolicy.daily(long, calendar: rewardCalendar("Asia/Seoul")).map(\.points) == [4_800, 4_800])
}

@Test func fractionsDoNotLeakIntoAnotherRewardDay() {
    let start = rewardDate("2026-09-17T23:59:57Z")
    let days = RewardPolicy.daily([rewardInterval(start, seconds: 6)], calendar: rewardCalendar())
    #expect(days.map(\.points) == [0, 0])
    #expect(days.map(\.creditedMilliseconds) == [3_000, 3_000])
}

@Test func rewardCalendarHandlesLeapDayAndDaylightSaving() {
    let leap = rewardDate("2028-02-28T23:59:54Z")
    #expect(RewardPolicy.daily([rewardInterval(leap, seconds: 12)], calendar: rewardCalendar()).map(\.points) == [1, 1])

    let newYork = rewardCalendar("America/New_York")
    let spring = RewardInterval(start: rewardDate("2026-03-08T05:00:00Z"),
                                end: rewardDate("2026-03-09T04:00:00Z"))
    let autumn = RewardInterval(start: rewardDate("2026-11-01T04:00:00Z"),
                                end: rewardDate("2026-11-02T05:00:00Z"))
    for interval in [spring, autumn] {
        let days = RewardPolicy.daily([interval], calendar: newYork)
        #expect(days.count == 1)
        #expect(days.first?.points == 4_800)
    }
    let repeatedHour = RewardInterval(start: rewardDate("2026-11-01T05:30:00Z"),
                                      end: rewardDate("2026-11-01T06:30:00Z"))
    #expect(RewardPolicy.total([repeatedHour], calendar: newYork) == 600)
}

@Test func malformedRewardIntervalsAreIgnored() {
    let start = rewardDate("2026-09-17T09:00:00Z")
    let invalid = [
        rewardInterval(start, seconds: 0),
        rewardInterval(start, seconds: -10),
        rewardInterval(start, seconds: 32 * 24 * 3_600),
        RewardInterval(start: Date(timeIntervalSince1970: .nan), end: start),
        RewardInterval(start: start, end: Date(timeIntervalSince1970: .infinity)),
        rewardInterval(Date(timeIntervalSince1970: -1e100), seconds: 600)
    ]
    #expect(RewardPolicy.daily(invalid, calendar: rewardCalendar()).isEmpty)
    #expect(RewardPolicy.total(invalid + [rewardInterval(start, seconds: 600)],
                               calendar: rewardCalendar()) == 100)
}

@Test func rewardIntervalsRoundTripWithoutPayFields() throws {
    let intervals = [rewardInterval(rewardDate("2026-09-17T09:00:00Z"), seconds: 600)]
    let encoded = try JSONEncoder().encode(intervals)
    let decoded = try JSONDecoder().decode([RewardInterval].self, from: encoded)
    #expect(decoded == intervals)
    #expect(RewardPolicy.total(decoded, calendar: rewardCalendar()) == 100)
}

@Test func rewardIntervalTraversalHasABoundedSupportedSpan() {
    let start = rewardDate("2026-09-01T00:00:00Z")
    let days = RewardPolicy.daily([rewardInterval(start, seconds: 31 * 24 * 3_600)],
                                  calendar: rewardCalendar())
    #expect(days.count == 31)
    #expect(days.allSatisfy { $0.points == RewardPolicy.pointsPerDay })
    #expect(RewardPolicy.calendar.timeZone.identifier == "Asia/Seoul")
}
