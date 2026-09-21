package com.minseo.piyakbank.core

import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class RewardPolicyTest {
    private val start = Instant.parse("2026-09-20T15:00:00Z").toEpochMilli() // KST midnight

    @Test fun fractionsCarryAcrossSessionsButOverlappingReceiptsAreUnited() {
        assertEquals(1L, RewardPolicy.total(listOf(Interval(start, start + 3000), Interval(start + 3000, start + 6000))))
        assertEquals(1L, RewardPolicy.total(listOf(Interval(start, start + 6000), Interval(start, start + 6000))))
        assertEquals(2L, RewardPolicy.total(listOf(Interval(start, start + 9000), Interval(start + 3000, start + 12_000))))
    }

    @Test fun pointBoundariesAreIntegerAndDeterministic() {
        assertEquals(0L, RewardPolicy.total(listOf(Interval(start, start + 5999))))
        assertEquals(1L, RewardPolicy.total(listOf(Interval(start, start + 6000))))
        assertEquals(100L, RewardPolicy.total(listOf(Interval(start, start + 600_000))))
    }

    @Test fun capIsEightHoursPerFixedKoreanDay() {
        assertEquals(4800L, RewardPolicy.total(listOf(Interval(start, start + 86_400_000))))
        assertEquals(9600L, RewardPolicy.total(listOf(Interval(start, start + 172_800_000))))
    }

    @Test fun midnightDoesNotCarryRemainderBetweenRewardDays() {
        val midnight = start + 86_400_000
        val result = RewardPolicy.daily(listOf(Interval(midnight - 3000, midnight + 3000)))
        assertEquals(2, result.size)
        assertEquals(0L, result.sumOf { it.points })
    }

    @Test fun malformedIntervalsCannotProducePointsOrUnboundedCalendarWalks() {
        assertEquals(0L, RewardPolicy.total(listOf(Interval(Long.MIN_VALUE, Long.MAX_VALUE),
            Interval(start, start), Interval(start + 1, start), Interval(start, start + 32 * 86_400_000L))))
    }

    @Test fun receiptInputOrderingDoesNotAffectUnionOrCap() {
        val intervals = listOf(Interval(start + 6000, start + 12000), Interval(start, start + 9000),
            Interval(start + 36000, start + 39000), Interval(start + 30000, start + 36000))
        assertEquals(RewardPolicy.daily(intervals), RewardPolicy.daily(intervals.reversed()))
        assertEquals(3L, RewardPolicy.total(intervals))
    }
}
