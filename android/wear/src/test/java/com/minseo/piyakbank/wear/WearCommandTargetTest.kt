package com.minseo.piyakbank.wear

import org.junit.Assert.*
import org.junit.Test

class WearCommandTargetTest {
    private val phone = PhoneState("install-A", 1, 1000, true, "shift-A", true, 10, 20, 1, 10000, "", "stage-A", emptyMap())

    @Test fun checkpointsAndEarningsDoNotInvalidateVisibleControls() {
        assertTrue(phone.commandTarget().matches(phone.copy(revision = 2, time = 2000, earnings = 30)))
    }
    @Test fun newShiftCannotReceiveOldConfirmation() {
        assertFalse(phone.commandTarget().matches(phone.copy(session = "shift-B")))
    }
    @Test fun pauseThenResumeCannotReuseConfirmationFromEarlierStage() {
        assertFalse(phone.commandTarget().matches(phone.copy(stage = "stage-C", working = true)))
    }
    @Test fun dataResetCannotReuseOldControl() {
        assertFalse(phone.commandTarget().matches(phone.copy(instance = "install-B")))
    }
    @Test fun changedWorkingStateAndEndedShiftInvalidateControl() {
        assertFalse(phone.commandTarget().matches(phone.copy(working = false)))
        assertFalse(phone.commandTarget().matches(phone.copy(session = "", stage = "")))
    }
}
