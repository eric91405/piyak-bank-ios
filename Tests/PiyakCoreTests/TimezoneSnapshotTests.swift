import Foundation
import SwiftData
import Testing
@testable import PiyakCore

private func snapshotDate(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private func snapshotCalendar(_ timezone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timezone)!
    return calendar
}
private func completedSnapshot(_ records: [[WageSegment]], at date: Date,
                               calendar: Calendar) -> SessionSnapshot {
    var completed = CompletedEarningsSnapshot(at: date, calendar: calendar)
    for record in records { completed.add(record, until: date) }
    return SessionSnapshot(isRunning: false, isPaused: false, accrued: 0, wage: 0,
                           capturedAt: date, completedToday: completed.amount(on: date, calendar: calendar),
                           completedEarnings: completed)
}

@Test func completedEarningsFollowWestwardTimezoneChangeWithoutPhoneRefresh() {
    let captured = snapshotDate("2026-09-21T10:00:00Z")
    let records = [[WageSegment(start: snapshotDate("2026-09-20T16:00:00Z"),
                                end: snapshotDate("2026-09-20T17:00:00Z"), hourlyWage: 10_000)]]
    var snapshot = completedSnapshot(records, at: captured, calendar: snapshotCalendar("Asia/Seoul"))
    #expect(snapshot.today(at: captured, calendar: snapshotCalendar("Asia/Seoul")) == 10_000)
    #expect(snapshot.today(at: captured, calendar: snapshotCalendar("America/Los_Angeles")) == 0)

    snapshot.segments = [WageSegment(start: snapshotDate("2026-09-21T09:00:00Z"), hourlyWage: 12_000)]
    #expect(snapshot.today(at: captured, calendar: snapshotCalendar("Asia/Seoul")) == 22_000)
    #expect(snapshot.today(at: captured, calendar: snapshotCalendar("America/Los_Angeles")) == 12_000)
}

@Test func completedEarningsFollowEastwardTimezoneChangeWithoutPhoneRefresh() {
    let captured = snapshotDate("2026-09-20T20:00:00Z")
    let records = [[WageSegment(start: snapshotDate("2026-09-20T08:00:00Z"),
                                end: snapshotDate("2026-09-20T09:00:00Z"), hourlyWage: 10_000)]]
    let snapshot = completedSnapshot(records, at: captured, calendar: snapshotCalendar("America/Los_Angeles"))
    #expect(snapshot.today(at: captured, calendar: snapshotCalendar("America/Los_Angeles")) == 10_000)
    #expect(snapshot.today(at: captured, calendar: snapshotCalendar("Asia/Seoul")) == 0)
}

@Test func completedEarningsExpireAtTheReceivingCalendarsMidnight() {
    let captured = snapshotDate("2026-09-21T23:30:00Z")
    let calendar = snapshotCalendar("Etc/UTC")
    let records = [[WageSegment(start: snapshotDate("2026-09-21T22:00:00Z"),
                                end: snapshotDate("2026-09-21T23:00:00Z"), hourlyWage: 10_000)]]
    let snapshot = completedSnapshot(records, at: captured, calendar: calendar)
    #expect(snapshot.today(at: captured, calendar: calendar) == 10_000)
    #expect(snapshot.today(at: snapshotDate("2026-09-22T00:00:00Z"), calendar: calendar) == 0)
}

@Test func completedEarningsPreserveFractionalCarryWithinEachRecord() {
    let midnight = snapshotDate("2026-09-21T00:00:00Z")
    let captured = midnight.addingTimeInterval(60)
    let calendar = snapshotCalendar("Etc/UTC")
    let crossing = [WageSegment(start: midnight.addingTimeInterval(-1),
                                end: midnight.addingTimeInterval(1), hourlyWage: 10_000)]
    // Two individually sub-won records must remain zero rather than rounding up
    // when their numerators are accidentally combined with another record.
    let fractional = [WageSegment(start: midnight.addingTimeInterval(2),
                                  end: midnight.addingTimeInterval(3), hourlyWage: 2_000)]
    let records = [crossing, fractional, fractional]
    let snapshot = completedSnapshot(records, at: captured, calendar: calendar)
    #expect(snapshot.today(at: captured, calendar: calendar) == 3)
    #expect(snapshot.today(at: captured, calendar: calendar) == records.reduce(0) {
        $0 + EarningsCalculator.earned(on: captured, segments: $1, until: captured, calendar: calendar)
    })
}

@Test func completedEarningsRespectSpringAndAutumnDaylightSavingBoundaries() {
    let calendar = snapshotCalendar("America/New_York")
    for (start, end, expected) in [
        ("2026-03-08T04:00:00Z", "2026-03-09T03:00:00Z", 220_000),
        ("2026-11-01T03:00:00Z", "2026-11-02T04:00:00Z", 240_000)
    ] {
        let captured = snapshotDate(end)
        let records = [[WageSegment(start: snapshotDate(start), end: captured, hourlyWage: 10_000)]]
        let snapshot = completedSnapshot(records, at: captured, calendar: calendar)
        #expect(snapshot.today(at: captured, calendar: calendar) == expected)
        #expect(snapshot.today(at: captured, calendar: calendar) == EarningsCalculator.earned(
            on: captured, segments: records[0], until: captured, calendar: calendar))
    }
}

@Test func completedEarningsPayloadIsBoundedAndPreservesCalendarChoice() throws {
    let captured = snapshotDate("2026-09-21T10:00:00Z")
    var calendar = Calendar(identifier: .buddhist)
    calendar.timeZone = TimeZone(identifier: "Asia/Bangkok")!
    let record = [WageSegment(start: captured.addingTimeInterval(-3_600), end: captured, hourlyWage: 10_000)]
    let snapshot = completedSnapshot(Array(repeating: record, count: 1_000), at: captured, calendar: calendar)
    let data = try JSONEncoder().encode(snapshot)
    #expect(data.count < 8_192)
    let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)
    #expect(decoded == snapshot)
    #expect(decoded.today(at: captured, calendar: calendar) == 10_000_000)
    #expect((decoded.completedEarnings?.days.count ?? 0) < 80)
}

@Test func completedEarningsMatchRecordAccountingInEverySystemTimezone() {
    let captured = snapshotDate("2026-09-21T10:00:00Z")
    let start = captured.addingTimeInterval(-30 * 3_600 - 0.123)
    let records = [
        [WageSegment(start: start, end: start.addingTimeInterval(20 * 3_600), hourlyWage: 999_983),
         WageSegment(start: start.addingTimeInterval(20 * 3_600), end: start.addingTimeInterval(21 * 3_600), hourlyWage: 0),
         WageSegment(start: start.addingTimeInterval(21 * 3_600), end: captured, hourlyWage: 12_345)],
        [WageSegment(start: captured.addingTimeInterval(-10_000), end: captured, hourlyWage: 9_863)]
    ]
    let snapshot = completedSnapshot(records, at: captured, calendar: snapshotCalendar("Asia/Seoul"))
    for identifier in TimeZone.knownTimeZoneIdentifiers {
        let calendar = snapshotCalendar(identifier)
        let expected = records.reduce(0) {
            $0 + EarningsCalculator.earned(on: captured, segments: $1, until: captured, calendar: calendar)
        }
        #expect(snapshot.today(at: captured, calendar: calendar) == expected)
    }
}

@Test func oldSnapshotWithoutTimezoneDoesNotMislabelCompletedPay() throws {
    let captured = snapshotDate("2026-09-21T10:00:00Z")
    let oldSnapshot = SessionSnapshot(isRunning: true, isPaused: false, accrued: 0, wage: 10_000,
        segments: [WageSegment(start: captured.addingTimeInterval(-3_600), hourlyWage: 10_000)],
        capturedAt: captured, completedToday: 90_000)
    let data = try JSONEncoder().encode(oldSnapshot)
    let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)
    #expect(decoded.completedEarnings == nil)
    #expect(decoded.today(at: captured, calendar: snapshotCalendar("Asia/Seoul")) == 10_000)
    #expect(decoded.today(at: captured, calendar: snapshotCalendar("America/Los_Angeles")) == 10_000)
}

@Test @MainActor func completedEarningsStoreSkipsActiveAndExpiredRecords() throws {
    let schema = Schema([CatalogItem.self, OwnedItem.self, PointTransaction.self, WorkSession.self, RewardReceipt.self])
    let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    container.mainContext.autosaveEnabled = false
    let store = EconomyStore(context: container.mainContext)
    let captured = snapshotDate("2026-09-21T10:00:00Z")
    let calendar = snapshotCalendar("Asia/Seoul")
    let completed = WorkSession(startedAt: captured.addingTimeInterval(-3_600), wage: 10_000)
    completed.segments = [WageSegment(start: completed.startedAt, end: captured, hourlyWage: 10_000)]
    completed.endedAt = captured
    completed.isActive = false
    let old = WorkSession(startedAt: captured.addingTimeInterval(-10 * 86_400), wage: 20_000)
    old.endedAt = old.startedAt.addingTimeInterval(3_600)
    old.segments = [WageSegment(start: old.startedAt, end: old.endedAt, hourlyWage: 20_000)]
    old.isActive = false
    let active = WorkSession(startedAt: captured.addingTimeInterval(-3_600), wage: 30_000)
    for session in [completed, old, active] { container.mainContext.insert(session) }
    try container.mainContext.save()
    let snapshot = try store.completedEarningsSnapshot(at: captured, calendar: calendar)
    #expect(snapshot.amount(on: captured, calendar: calendar) == 10_000)
}
