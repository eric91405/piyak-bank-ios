package com.minseo.piyakbank.platform

import com.minseo.piyakbank.core.ClockSample
import com.minseo.piyakbank.core.DomainEngine
import org.junit.Assert.*
import org.junit.Test

class SettingsPolicyTest {
    private val now = ClockSample(1_790_000_000_000, 100_000, "boot")
    private fun initial() = PersistentState(DomainEngine.fresh(now), UserSettings(onboarded = true), instanceId = "bank")

    @Test fun independentDelayedSettingsIntentsPreserveAlreadyCommittedFields() {
        val original = initial()
        val changedWage = SettingsPolicy.wage(original, 25_000)
        val changedMotion = SettingsPolicy.animation(changedWage, false)
        val changedNotifications = SettingsPolicy.notifications(changedMotion, true)
        val result = SettingsPolicy.reminderMinutes(changedNotifications, 30)
        assertEquals(UserSettings(25_000, true, true, 30, false), result.settings)
        assertEquals(original.data, result.data)
        assertEquals(original.instanceId, result.instanceId)
    }

    @Test fun wageIntentRechecksWorkingAndPausedSessionAfterOtherDeviceStarts() {
        val original = initial()
        val running = original.copy(data = DomainEngine.start(original.data, original.settings.wage, now, "work"))
        val paused = running.copy(data = DomainEngine.pause(running.data, now))
        for (state in listOf(running, paused)) {
            try { SettingsPolicy.wage(state, 25_000); fail("Active session must reject wage changes") }
            catch (_: IllegalArgumentException) { /* expected */ }
            assertEquals(10_000, state.settings.wage)
        }
    }

    @Test fun nonWagePreferencesRemainUsableDuringWork() {
        val original = initial()
        val running = original.copy(data = DomainEngine.start(original.data, original.settings.wage, now, "work"))
        val modified = SettingsPolicy.notifications(SettingsPolicy.animation(SettingsPolicy.reminderMinutes(running, 120), false), true)
        assertEquals(running.data, modified.data)
        assertEquals(UserSettings(10_000, true, true, 120, false), modified.settings)
    }

    @Test fun invalidWageOrReminderCannotAlterExistingState() {
        val original = initial()
        for (value in listOf(0, 1_000_001)) {
            try { SettingsPolicy.wage(original, value); fail("Invalid wage accepted") }
            catch (_: IllegalArgumentException) { /* expected */ }
        }
        try { SettingsPolicy.reminderMinutes(original, 1); fail("Invalid interval accepted") }
        catch (_: IllegalArgumentException) { /* expected */ }
        assertEquals(UserSettings(onboarded = true), original.settings)
    }
}
