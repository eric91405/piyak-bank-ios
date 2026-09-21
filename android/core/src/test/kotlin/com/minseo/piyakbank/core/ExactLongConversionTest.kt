package com.minseo.piyakbank.core

import java.math.BigInteger
import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows

class ExactLongConversionTest {
    @Test fun signedLongEndpointsAndZeroRemainExact() {
        listOf(Long.MIN_VALUE, -1, 0, 1, Long.MAX_VALUE).forEach {
            assertEquals(it, BigInteger.valueOf(it).toLongExactCompat())
        }
    }

    @Test fun overflowOnEitherSideNeverTruncatesIntoMoney() {
        assertThrows(ArithmeticException::class.java) { BigInteger.valueOf(Long.MAX_VALUE).add(BigInteger.ONE).toLongExactCompat() }
        assertThrows(ArithmeticException::class.java) { BigInteger.valueOf(Long.MIN_VALUE).subtract(BigInteger.ONE).toLongExactCompat() }
    }
}
