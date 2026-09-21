package com.minseo.piyakbank.wear

import org.junit.Assert.*
import org.junit.Test

class SnapshotRequestGateTest {
    @Test fun initialUnsolicitedPushCannotReplaceRequestBeforeCorrelatedReply() {
        val gate = SnapshotRequestGate()
        assertTrue(gate.begin("phone", "request-A", 1000))
        // The phone emits a normal state update while servicing our request.
        assertFalse(gate.matches("phone", null))
        assertFalse(gate.canStart("phone", 1100))
        assertFalse(gate.begin("phone", "request-B", 1100))
        assertTrue(gate.matches("phone", "request-A"))
        assertTrue(gate.complete("phone", "request-A"))
        assertTrue(gate.canStart("phone", 1200))
    }

    @Test fun anotherNodeCannotCompleteSelectedPhonesRequest() {
        val gate = SnapshotRequestGate()
        gate.begin("phone-A", "request", 1000)
        assertFalse(gate.complete("phone-B", "request"))
        assertTrue(gate.matches("phone-A", "request"))
    }

    @Test fun expiredRequestCanRetryAndOldReplyCannotCancelNewNonce() {
        val gate = SnapshotRequestGate()
        gate.begin("phone", "old", 1000)
        assertFalse(gate.canStart("phone", 5999))
        assertTrue(gate.canStart("phone", 6000))
        assertTrue(gate.begin("phone", "new", 6000))
        assertFalse(gate.complete("phone", "old"))
        assertTrue(gate.matches("phone", "new"))
    }

    @Test fun switchingPhonesClearsAllOldCorrelation() {
        val gate = SnapshotRequestGate()
        gate.begin("phone-A", "old", 1000)
        gate.clear()
        assertTrue(gate.begin("phone-B", "new", 1100))
        assertFalse(gate.matches("phone-A", "old"))
        assertTrue(gate.complete("phone-B", "new"))
    }

    @Test fun completedResponseIsConsumedOnlyOnce() {
        val gate = SnapshotRequestGate()
        gate.begin("phone", "request", 1000)
        assertTrue(gate.complete("phone", "request"))
        assertFalse(gate.matches("phone", "request"))
        assertFalse(gate.complete("phone", "request"))
    }

    @Test fun elapsedClockResetDoesNotLeaveRequestPermanentlyPending() {
        val gate = SnapshotRequestGate()
        gate.begin("phone", "old", 100_000)
        assertTrue(gate.canStart("phone", 100))
        assertTrue(gate.begin("phone", "new", 100))
        assertFalse(gate.matches("phone", "old"))
    }

    @Test fun unrelatedPushAndIncorrectResponseDoNotExtendTimeout() {
        val gate = SnapshotRequestGate()
        gate.begin("phone", "request", 1000)
        for (time in listOf(1500L, 3000L, 5999L)) {
            assertFalse(gate.complete("phone", "unrelated"))
            assertFalse(gate.canStart("phone", time))
        }
        assertTrue(gate.canStart("phone", 6000))
    }
}
