package com.minseo.piyakbank.platform

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.minseo.piyakbank.core.DomainEngine
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

/** Actual isolated SQLite + production reminder orchestration, with controlled OS grants/alarms. */
@RunWith(AndroidJUnit4::class)
class ExceptionFlowsTest {
    private lateinit var app: PiyakApplication
    private lateinit var database: BankDatabase
    private lateinit var repository: PiyakRepository
    private lateinit var databaseName: String
    private val system = RecordingReminderSystem()
    private var boundaryFailure: Exception? = null

    @Before fun setup() = runBlocking {
        app = ApplicationProvider.getApplicationContext()
        assumeTrue("Exception fixtures require the isolated QA app", app.packageName == "com.minseo.piyakbank.uitest")
        databaseName = "exceptions-${UUID.randomUUID()}.db"
        database = BankDatabase(app, databaseName)
        repository = newRepository()
        repository.refresh()
        repository.mutate("합성 근무") { state, now ->
            state.copy(data = DomainEngine.start(state.data, state.settings.wage, now),
                settings = state.settings.copy(onboarded = true, notificationsEnabled = true, reminderMinutes = 15))
        }
        assertNull(repository.ui.value.error)
        system.cancellations = 0
    }

    private fun newRepository() = PiyakRepository(app, database) { state, delivered ->
        boundaryFailure?.let { throw it }
        ReminderScheduler.synchronize(state, delivered, system)
    }

    @After fun cleanup() {
        if (::repository.isInitialized) repository.scope.cancel()
        if (::database.isInitialized) database.close()
        if (::databaseName.isInitialized) app.deleteDatabase(databaseName)
    }

    @Test fun permissionDenialAndRegrantRecheckCancelThenScheduleWithoutChangingBank() = runBlocking {
        val before = repository.snapshot()
        assertNotNull(system.scheduled)
        system.allowed = false
        repository.deliverReminder()
        assertNull(system.scheduled)
        assertEquals(1, system.cancellations)
        assertEquals(0, system.notifications)
        assertEquals(before, repository.snapshot())

        system.elapsedMillis += 10_000
        system.allowed = true
        repository.deliverReminder()
        assertEquals(system.elapsedMillis + 15 * 60_000L, system.scheduled!!.dueMillis)
        assertEquals(0, system.notifications) // A late callback after regrant is not a new due alarm.
        assertEquals(before, repository.snapshot())
    }

    @Test fun duplicateEarlyAndDelayedAlarmsKeepOneCadenceAndNeverMintRewards() = runBlocking {
        val before = repository.snapshot()
        val firstDue = system.scheduled!!.dueMillis
        repository.deliverReminder()
        assertEquals(firstDue, system.scheduled!!.dueMillis)
        assertEquals(0, system.notifications)
        system.elapsedMillis = firstDue
        repository.deliverReminder()
        assertEquals(1, system.notifications)
        assertEquals(firstDue + 15 * 60_000L, system.scheduled!!.dueMillis)
        repository.deliverReminder()
        assertEquals(1, system.notifications)
        system.elapsedMillis += 90 * 60_000L
        repository.deliverReminder()
        assertEquals(2, system.notifications)
        assertEquals(system.elapsedMillis + 15 * 60_000L, system.scheduled!!.dueMillis)
        assertEquals(before, repository.snapshot())
    }

    @Test fun pauseAndDisableDefeatPreviouslyDeliveredAlarms() = runBlocking {
        val oldDue = system.scheduled!!.dueMillis
        repository.mutate("휴식") { state, now -> state.copy(data = DomainEngine.pause(state.data, now)) }
        val paused = repository.snapshot()
        assertNull(system.scheduled)
        system.elapsedMillis = oldDue
        repository.deliverReminder()
        assertNull(system.scheduled)
        assertEquals(0, system.notifications)
        assertEquals(paused, repository.snapshot())

        repository.mutate("재개") { state, now -> state.copy(data = DomainEngine.resume(state.data, state.settings.wage, now)) }
        assertNotNull(system.scheduled)
        repository.updateNotifications(false)
        val disabled = repository.snapshot()
        repository.deliverReminder()
        assertNull(system.scheduled)
        assertEquals(0, system.notifications)
        assertEquals(disabled, repository.snapshot())
    }

    @Test fun intervalChangeAndInvalidPersistedScheduleRebaseTheDueTime() = runBlocking {
        val beforeData = repository.snapshot().data
        repository.updateReminderMinutes(30)
        assertEquals(system.elapsedMillis + 30 * 60_000L, system.scheduled!!.dueMillis)
        system.scheduled = system.scheduled!!.copy(dueMillis = Long.MAX_VALUE)
        repository.deliverReminder()
        assertEquals(system.elapsedMillis + 30 * 60_000L, system.scheduled!!.dueMillis)
        assertEquals(0, system.notifications)
        assertEquals(beforeData, repository.snapshot().data)
    }

    @Test fun processRecoveryReschedulesEnabledWorkButHonorsPersistedDisable() = runBlocking {
        val before = repository.snapshot()
        system.scheduled = null // OS can drop an alarm across process/package lifecycle events.
        repository.scope.cancel()
        repository = newRepository()
        repository.refresh()
        assertNotNull(system.scheduled)
        val recovered = repository.snapshot()
        assertEquals(before.data.active!!.id, recovered.data.active!!.id)
        assertEquals(before.data.records, recovered.data.records)
        assertEquals(before.data.ledger, recovered.data.ledger)
        assertEquals(before.settings, recovered.settings)
        repository.updateNotifications(false)
        repository.scope.cancel()
        repository = newRepository()
        repository.refresh()
        assertNull(system.scheduled)
        assertFalse(repository.snapshot().settings.notificationsEnabled)
        assertEquals(before.data.ledger, repository.snapshot().data.ledger)
    }

    @Test fun permissionRevokedBetweenCheckAndNotifyCancelsSafely() = runBlocking {
        val before = repository.snapshot()
        system.elapsedMillis = system.scheduled!!.dueMillis
        system.revokeOnNotify = true
        repository.deliverReminder()
        assertNull(system.scheduled)
        assertEquals(0, system.notifications)
        assertEquals(before, repository.snapshot())
    }

    @Test fun systemSchedulingFailureCannotUndoCommittedSettingsOrDamageMoney() = runBlocking {
        val before = repository.snapshot()
        boundaryFailure = IllegalStateException("Synthetic AlarmManager failure")
        repository.updateReminderMinutes(30)
        val after = repository.snapshot()
        assertEquals(30, after.settings.reminderMinutes)
        assertEquals(before.data, after.data)
        assertEquals(before.revision + 1, after.revision)
        assertNull(repository.ui.value.error)
        assertFalse(repository.ui.value.busy)
    }

    @Test fun cancellationOfSystemSynchronizationPropagatesAfterAnAtomicCommit() = runBlocking {
        val before = repository.snapshot()
        boundaryFailure = CancellationException("Synthetic lifecycle cancellation")
        try { repository.updateAnimation(false); fail("Cancellation was swallowed") }
        catch (_: CancellationException) { }
        val after = repository.snapshot()
        assertFalse(after.settings.animationEnabled)
        assertEquals(before.data, after.data)
        assertEquals(before.revision + 1, after.revision)
        assertNull(repository.ui.value.error)
        assertFalse(repository.ui.value.busy)
    }

    @Test fun realAndroidCancellationClearsScheduleWithoutRequestingPermission() = runBlocking {
        val before = repository.snapshot()
        val prefs = app.getSharedPreferences("reminder_schedule", Context.MODE_PRIVATE)
        prefs.edit().putString("token", "synthetic-stale").putLong("due", 1L).commit()
        ReminderScheduler.synchronize(app, before.copy(settings = before.settings.copy(notificationsEnabled = false)), delivered = true)
        assertFalse(prefs.contains("token"))
        assertFalse(prefs.contains("due"))
        assertEquals(before, repository.snapshot())
    }

    private class RecordingReminderSystem : ReminderSystem {
        override var elapsedMillis = 1_000_000L
        var allowed = true
        var scheduled: ReminderSchedule? = null
        var notifications = 0
        var cancellations = 0
        var revokeOnNotify = false
        override fun notificationsAvailable() = allowed
        override fun readSchedule() = scheduled
        override fun cancel() { scheduled = null; cancellations++ }
        override fun notifyWork() {
            if (revokeOnNotify) throw SecurityException("Synthetic permission revocation")
            notifications++
        }
        override fun schedule(value: ReminderSchedule) { scheduled = value }
    }
}
