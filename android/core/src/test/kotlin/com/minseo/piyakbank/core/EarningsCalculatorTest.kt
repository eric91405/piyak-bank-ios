package com.minseo.piyakbank.core

import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class EarningsCalculatorTest {
    private fun ms(value: String) = Instant.parse(value).toEpochMilli()

    @Test fun exactMaximumWageHourAvoidsFloatingPointLoss() {
        val start = ms("2026-09-21T00:00:00Z")
        assertEquals(1_000_000L, EarningsCalculator.total(listOf(Segment(start, start + 3_600_000, 1_000_000)), start + 3_600_000))
    }

    @Test fun fractionalWonCarryAcrossMultipleWorkingSegments() {
        val segments = listOf(Segment(0, 1800, 1000), Segment(1800, 3000, 0), Segment(3000, 4800, 1000))
        assertEquals(1L, EarningsCalculator.total(segments, 4800))
        assertEquals(3600L, EarningsCalculator.workingMillis(segments, 4800))
    }

    @Test fun midnightAllocationsSumToWholeRecord() {
        val start = ms("2026-09-21T14:59:59Z")
        val segments = listOf(Segment(start, start + 7200, 1000))
        val daily = EarningsCalculator.daily(segments, start + 7200, ZoneId.of("Asia/Seoul"))
        assertEquals(listOf(0L, 2L), daily.map { it.amount })
        assertEquals(EarningsCalculator.total(segments, start + 7200), daily.sumOf { it.amount })
    }

    @Test fun springForwardUsesRealHoursInLocalDay() {
        val start = ms("2026-03-08T05:00:00Z")
        val end = ms("2026-03-09T04:00:00Z")
        val daily = EarningsCalculator.daily(listOf(Segment(start, end, 1000)), end, ZoneId.of("America/New_York"))
        assertEquals(1, daily.size)
        assertEquals(23_000L, daily.single().amount)
    }

    @Test fun fallBackUsesTwentyFiveRealHours() {
        val start = ms("2026-11-01T04:00:00Z")
        val end = ms("2026-11-02T05:00:00Z")
        assertEquals(25_000L, EarningsCalculator.daily(listOf(Segment(start, end, 1000)), end,
            ZoneId.of("America/New_York")).single().amount)
    }

    @Test fun runningSegmentClipsToNowAndFutureRecordPaysNothingYet() {
        assertEquals(5000L, EarningsCalculator.total(listOf(Segment(0, null, 10_000)), 1_800_000))
        assertEquals(0L, EarningsCalculator.total(listOf(Segment(1000, 4000, 10_000)), 0))
    }

    @Test fun extremeCivilDateProductUsesBigIntegerWithoutOverflow() {
        val start = ms("2000-01-01T00:00:00Z")
        val end = ms("2500-01-01T00:00:00Z")
        assertEquals((end - start) / 3_600_000 * 1_000_000, EarningsCalculator.total(listOf(Segment(start, end, 1_000_000)), end))
    }

    @Test fun focusedDayCalculationMatchesDailyFractionsInEveryTestedTimeZone() {
        val start = ms("2026-11-01T03:59:59Z")
        val end = start + 50 * 3_600_000
        val segments = listOf(Segment(start, start + 1300, 1000), Segment(start + 1300, start + 3800, 0),
            Segment(start + 3800, end, 10_123))
        for (zone in listOf("Asia/Seoul", "America/New_York", "Pacific/Chatham", "UTC")) {
            val id = ZoneId.of(zone)
            val daily = EarningsCalculator.daily(segments, end, id)
            for (day in daily) assertEquals(day.amount, EarningsCalculator.earnedOn(segments, day.day, end, id))
            assertEquals(0L, EarningsCalculator.earnedOn(segments, daily.first().day.minusDays(1), end, id))
            assertEquals(0L, EarningsCalculator.earnedOn(segments, daily.last().day.plusDays(1), end, id))
        }
    }

    @Test fun focusedDayCalculationDoesNotReallocateFractionToAnEmptyDay() {
        val first = ms("2026-09-20T00:00:00Z")
        val second = ms("2026-09-22T00:00:00Z")
        val segments = listOf(Segment(first, first + 1800, 1000), Segment(second, second + 1800, 1000))
        val zone = ZoneId.of("UTC")
        val days = EarningsCalculator.daily(segments, second + 1800, zone)
        assertEquals(0L, EarningsCalculator.earnedOn(segments, days.first().day.plusDays(1), second + 1800, zone))
        assertEquals(1L, EarningsCalculator.earnedOn(segments, days.last().day, second + 1800, zone))
    }
}
