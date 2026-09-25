package com.minseo.piyakbank.platform

import android.Manifest
import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import com.minseo.piyakbank.MainActivity
import com.minseo.piyakbank.R
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

internal data class ReminderSchedule(val token: String, val dueMillis: Long)

/** System boundary: tests can revoke permission or fail delivery without changing device grants. */
internal interface ReminderSystem {
    val elapsedMillis: Long
    fun notificationsAvailable(): Boolean
    fun readSchedule(): ReminderSchedule?
    fun cancel()
    fun notifyWork()
    fun schedule(value: ReminderSchedule)
}

object ReminderScheduler {
    private const val CHANNEL = "work_reminders"
    private fun pending(context: Context) = PendingIntent.getBroadcast(context, 7, Intent(context, ReminderReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    /** App-wide permission and the individual reminder channel can be disabled independently. */
    fun notificationsAvailable(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        val manager = context.getSystemService(NotificationManager::class.java)
        return manager.areNotificationsEnabled() && manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
    }

    fun synchronize(context: Context, state: PersistentState, delivered: Boolean = false) {
        synchronize(state, delivered, AndroidReminderSystem(context))
    }

    internal fun synchronize(state: PersistentState, delivered: Boolean, system: ReminderSystem) {
        val active = state.data.active
        if (!state.settings.notificationsEnabled || !system.notificationsAvailable() || active?.tracking?.working != true) {
            system.cancel(); return
        }
        val interval = state.settings.reminderMinutes * 60_000L
        val token = "${state.instanceId}:${active.id}:${active.tracking.anchor.bootId}:$interval"
        val now = system.elapsedMillis
        val previous = system.readSchedule()
        var due = previous?.dueMillis ?: 0L
        // A stale/rebooted or corrupt schedule must not suppress reminders indefinitely.
        val currentSchedule = previous?.token == token && due > 0 && due <= now + interval
        if (!currentSchedule) due = now + interval
        if (delivered && currentSchedule && now >= due) {
            try { system.notifyWork() }
            catch (_: SecurityException) {
                // Permission can change after the availability check. Clear the alarm, not bank data.
                system.cancel(); return
            }
            due += interval
            if (due <= now) due = now + interval
        }
        // Keep the original cadence on each UI checkpoint. Android may delay inexact alarms.
        system.schedule(ReminderSchedule(token, due))
    }

    private class AndroidReminderSystem(private val context: Context) : ReminderSystem {
        private val manager = context.getSystemService(NotificationManager::class.java)
        private val alarms = context.getSystemService(AlarmManager::class.java)
        private val prefs = context.getSharedPreferences("reminder_schedule", Context.MODE_PRIVATE)
        init {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "근무 중 알림", NotificationManager.IMPORTANCE_DEFAULT).apply { description = "진행 중인 근무를 확인하도록 알려드려요." })
        }
        override val elapsedMillis get() = SystemClock.elapsedRealtime()
        override fun notificationsAvailable() = ReminderScheduler.notificationsAvailable(context)
        override fun readSchedule(): ReminderSchedule? {
            return try {
                val token = prefs.getString("token", null) ?: return null
                ReminderSchedule(token, prefs.getLong("due", 0))
            } catch (_: ClassCastException) { null }
        }
        override fun cancel() {
            alarms.cancel(pending(context))
            manager.cancel(7)
            prefs.edit().clear().apply()
        }
        override fun notifyWork() {
            if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) throw SecurityException("알림 권한이 해제됐어요.")
            val intent = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val open = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notification = Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification).setContentTitle("삐약이와 근무 중이에요")
                .setContentText("쉬는 중이라면 휴식을 눌러 주세요. 근무 상태를 확인해요.")
                .setContentIntent(open).setAutoCancel(true).setVisibility(Notification.VISIBILITY_PRIVATE).build()
            manager.notify(7, notification)
        }
        override fun schedule(value: ReminderSchedule) {
            alarms.setWindow(AlarmManager.ELAPSED_REALTIME_WAKEUP, maxOf(value.dueMillis, elapsedMillis + 1_000), 10 * 60_000L, pending(context))
            prefs.edit().putString("token", value.token).putLong("due", value.dueMillis).apply()
        }
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        val repo = (context.applicationContext as PiyakApplication).repository
        repo.scope.launch {
            try {
                repo.refresh()
                repo.deliverReminder()
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { /* Keep the original store; do not notify on unverified state. */ }
            finally { pending.finish() }
        }
    }
}

class RecoveryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED)) return
        val pending = goAsync()
        val repo = (context.applicationContext as PiyakApplication).repository
        repo.scope.launch { try { repo.refresh() } finally { pending.finish() } }
    }
}
