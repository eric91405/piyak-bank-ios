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
import kotlinx.coroutines.launch

object ReminderScheduler {
    private const val CHANNEL = "work_reminders"
    private fun pending(context: Context) = PendingIntent.getBroadcast(context, 7, Intent(context, ReminderReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun synchronize(context: Context, state: PersistentState, delivered: Boolean = false) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "근무 중 알림", NotificationManager.IMPORTANCE_DEFAULT).apply { description = "진행 중인 근무를 확인하도록 알려드려요." })
        val alarms = context.getSystemService(AlarmManager::class.java)
        val prefs = context.getSharedPreferences("reminder_schedule", Context.MODE_PRIVATE)
        val permitted = Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val active = state.data.active
        if (!state.settings.notificationsEnabled || !permitted || !manager.areNotificationsEnabled() || active?.tracking?.working != true) {
            alarms.cancel(pending(context)); manager.cancel(7); prefs.edit().clear().apply(); return
        }
        val interval = state.settings.reminderMinutes * 60_000L
        val token = "${state.instanceId}:${active.id}:${active.tracking.anchor.bootId}:$interval"
        val now = SystemClock.elapsedRealtime()
        var due = prefs.getLong("due", 0)
        val currentSchedule = prefs.getString("token", null) == token && due > 0
        if (!currentSchedule) due = now + interval
        if (delivered && currentSchedule && now >= due) {
            val intent = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val open = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notification = Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification).setContentTitle("삐약이와 근무 중이에요")
                .setContentText("쉬는 중이라면 휴식을 눌러 주세요. 근무 상태를 확인해요.")
                .setContentIntent(open).setAutoCancel(true).setVisibility(Notification.VISIBILITY_PRIVATE).build()
            manager.notify(7, notification)
            due += interval
            if (due <= now) due = now + interval
        }
        // Keep the original cadence on each UI checkpoint. Android may delay inexact alarms.
        prefs.edit().putString("token", token).putLong("due", due).apply()
        alarms.setWindow(AlarmManager.ELAPSED_REALTIME_WAKEUP, maxOf(due, now + 1_000), 10 * 60_000L, pending(context))
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
            } catch (_: Exception) { /* Keep the original store; do not notify on unverified state. */ }
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
