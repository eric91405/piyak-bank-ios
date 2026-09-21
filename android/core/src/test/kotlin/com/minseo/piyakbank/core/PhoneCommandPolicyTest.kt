package com.minseo.piyakbank.core

import org.junit.Assert.*
import org.junit.Test

class PhoneCommandPolicyTest {
    private val clock = ClockSample(1_790_000_000_000, 100_000, "boot")
    private fun after(millis: Long) = clock.copy(wallMillis = clock.wallMillis + millis, elapsedMillis = clock.elapsedMillis + millis)
    private fun working(id: String = "A") = DomainEngine.start(DomainEngine.fresh(clock), 10_000, clock, id)
    private fun token(data: AppState, instance: String = "bank") = WatchCommandPolicy.stageToken(instance, data)
    private fun apply(data: AppState, action: WatchAction, expected: AppState, now: ClockSample = after(6000), instance: String = "bank") =
        PhoneCommandPolicy.apply(data, instance, true, 10_000, action, expected.active?.id ?: "", token(expected), now)
    private fun rejects(block: () -> Unit) {
        try { block(); fail("Stale phone control must be rejected") } catch (_: IllegalArgumentException) { /* expected */ }
    }

    @Test fun oldFinishConfirmationCannotFinishNewShiftAfterWatchTransitions() {
        val old = working()
        val completed = DomainEngine.finish(old, after(6000))
        val next = DomainEngine.start(completed, 10_000, after(7000), "B")
        rejects { apply(next, WatchAction.FINISH, old, after(8000)) }
        assertEquals("B", next.active!!.id)
        assertEquals(1, next.receipts.size)
    }

    @Test fun oldPauseClickCannotPauseResumedSameSession() {
        val old = working()
        val resumed = DomainEngine.resume(DomainEngine.pause(old, after(1000)), 10_000, after(2000))
        rejects { apply(resumed, WatchAction.PAUSE, old) }
        assertTrue(resumed.active!!.tracking.working)
    }

    @Test fun oldResumeClickCannotResumeLaterPauseOrAnotherShift() {
        val firstPause = DomainEngine.pause(working(), after(1000))
        val secondPause = DomainEngine.pause(DomainEngine.resume(firstPause, 10_000, after(2000)), after(3000))
        rejects { apply(secondPause, WatchAction.RESUME, firstPause) }
        val completed = DomainEngine.finish(secondPause, after(4000))
        val otherPause = DomainEngine.pause(DomainEngine.start(completed, 10_000, after(5000), "B"), after(6000))
        rejects { apply(otherPause, WatchAction.RESUME, firstPause, after(7000)) }
    }

    @Test fun ordinaryCheckpointsDoNotInvalidatePhoneButtons() {
        val old = working()
        val checked = DomainEngine.checkpoint(old, after(3000))
        val paused = apply(checked, WatchAction.PAUSE, old)
        assertFalse(paused.active!!.tracking.working)
        val resumed = apply(paused, WatchAction.RESUME, paused, after(7000))
        val finished = apply(resumed, WatchAction.FINISH, resumed, after(13_000))
        assertNull(finished.active)
        assertEquals(2L, DomainEngine.balance(finished))
    }

    @Test fun startConfirmationCannotSurviveInterveningShiftOrWholeBankReset() {
        val idle = DomainEngine.fresh(clock)
        val completed = DomainEngine.finish(DomainEngine.start(idle, 10_000, clock, "A"), after(6000))
        rejects { apply(completed, WatchAction.START, idle) }
        rejects { apply(DomainEngine.fresh(after(6000)), WatchAction.START, idle, instance = "reset-bank") }
    }
}
