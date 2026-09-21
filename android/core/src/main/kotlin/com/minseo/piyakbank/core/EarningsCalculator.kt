package com.minseo.piyakbank.core

import java.math.BigInteger
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Integer multiplication precedes one division; fractions survive pauses and midnight. */
object EarningsCalculator {
    const val maximumWage = 1_000_000
    const val maximumSessionMillis = 7 * 24 * 60 * 60 * 1_000L
    private val hourlyDivisor = BigInteger.valueOf(3_600_000)
    data class DayAmount(val day: LocalDate, val amount: Long)

    fun total(segments: List<Segment>, untilMillis: Long): Long =
        segments.fold(BigInteger.ZERO) { sum, segment ->
            sum + numerator(segment, segment.startMillis, minOf(segment.endMillis ?: untilMillis, untilMillis))
        }.divide(hourlyDivisor).toLongExactCompat()

    fun daily(segments: List<Segment>, untilMillis: Long, zoneId: ZoneId): List<DayAmount> {
        val result = sortedMapOf<LocalDate, Long>()
        var cumulativeNumerator = BigInteger.ZERO
        var allocated = 0L
        segments.sortedBy { it.startMillis }.filter { it.hourlyWage > 0 }.forEach { segment ->
            var cursor = segment.startMillis
            val end = minOf(segment.endMillis ?: untilMillis, untilMillis)
            while (cursor < end) {
                val day = Instant.ofEpochMilli(cursor).atZone(zoneId).toLocalDate()
                val next = day.plusDays(1).atStartOfDay(zoneId).toInstant().toEpochMilli()
                requireDomain(next > cursor)
                val stop = minOf(end, next)
                cumulativeNumerator += numerator(segment, cursor, stop)
                val rounded = cumulativeNumerator.divide(hourlyDivisor).toLongExactCompat()
                result[day] = Math.addExact(result[day] ?: 0, rounded - allocated)
                allocated = rounded
                cursor = stop
            }
        }
        return result.map { DayAmount(it.key, it.value) }
    }

    fun workingMillis(segments: List<Segment>, untilMillis: Long): Long =
        segments.filter { it.hourlyWage > 0 }.fold(0L) { sum, segment ->
            Math.addExact(sum, maxOf(0, minOf(segment.endMillis ?: untilMillis, untilMillis) - segment.startMillis))
        }

    /** A single local day's amount without walking every historical calendar day. */
    fun earnedOn(segments: List<Segment>, day: LocalDate, untilMillis: Long, zoneId: ZoneId): Long {
        val start = day.atStartOfDay(zoneId).toInstant().toEpochMilli()
        val end = day.plusDays(1).atStartOfDay(zoneId).toInstant().toEpochMilli()
        if (segments.none { it.hourlyWage > 0 && it.startMillis < end &&
                minOf(it.endMillis ?: untilMillis, untilMillis) > start }) return 0
        var before = BigInteger.ZERO
        var through = BigInteger.ZERO
        segments.forEach { segment ->
            val stop = minOf(segment.endMillis ?: untilMillis, untilMillis)
            before += numerator(segment, segment.startMillis, minOf(stop, start))
            through += numerator(segment, segment.startMillis, minOf(stop, end))
        }
        return through.divide(hourlyDivisor).subtract(before.divide(hourlyDivisor)).toLongExactCompat()
    }

    private fun numerator(segment: Segment, from: Long, to: Long): BigInteger {
        requireDomain(Bounds.date(from) && Bounds.date(to) && segment.hourlyWage in 0..maximumWage)
        if (to <= from || segment.hourlyWage == 0) return BigInteger.ZERO
        return BigInteger.valueOf(to - from).multiply(BigInteger.valueOf(segment.hourlyWage.toLong()))
    }
}

/** BigInteger.longValueExact is unavailable on Android 8.0; keep the same overflow contract. */
internal fun BigInteger.toLongExactCompat(): Long {
    if (bitLength() > 63) throw ArithmeticException("BigInteger out of long range")
    return toLong()
}
