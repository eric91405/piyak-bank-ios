package com.minseo.piyakbank.core

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Reward currency depends only on timer-measured time, never wage or editable records. */
object RewardPolicy {
    const val millisecondsPerPoint = 6_000L
    const val dailyPointLimit = 4_800L
    const val pointsPerLevel = 4_800L
    const val dailyMillisecondsLimit = 28_800_000L
    const val maximumSessionMillis = 86_400_000L
    const val maximumIntervalMillis = 31 * 86_400_000L
    val zone: ZoneId = ZoneId.of("Asia/Seoul")
    data class RewardDay(val day: LocalDate, val creditedMillis: Long, val points: Long)

    fun daily(intervals: List<Interval>): List<RewardDay> {
        val united = mutableListOf<Interval>()
        intervals.filter(::valid).sortedWith(compareBy<Interval> { it.startMillis }.thenBy { it.endMillis })
            .forEach { interval ->
                val last = united.lastOrNull()
                if (last != null && interval.startMillis <= last.endMillis) {
                    united[united.lastIndex] = last.copy(endMillis = maxOf(last.endMillis, interval.endMillis))
                } else united += interval
            }
        val byDay = sortedMapOf<LocalDate, Long>()
        united.forEach { interval ->
            var cursor = interval.startMillis
            while (cursor < interval.endMillis) {
                val day = Instant.ofEpochMilli(cursor).atZone(zone).toLocalDate()
                val next = day.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
                val stop = minOf(interval.endMillis, next)
                byDay[day] = minOf(dailyMillisecondsLimit, (byDay[day] ?: 0) + stop - cursor)
                cursor = stop
            }
        }
        return byDay.map { RewardDay(it.key, it.value, it.value / millisecondsPerPoint) }
    }

    fun total(intervals: List<Interval>): Long = daily(intervals).sumOf { it.points }

    internal fun valid(interval: Interval): Boolean = Bounds.date(interval.startMillis) &&
        Bounds.date(interval.endMillis) && interval.endMillis > interval.startMillis &&
        interval.endMillis - interval.startMillis <= maximumIntervalMillis
}
