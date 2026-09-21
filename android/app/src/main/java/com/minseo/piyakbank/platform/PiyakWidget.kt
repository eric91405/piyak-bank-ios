package com.minseo.piyakbank.platform

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.minseo.piyakbank.MainActivity
import com.minseo.piyakbank.R
import com.minseo.piyakbank.core.*
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

class PiyakWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val pending = goAsync()
        val repo = (context.applicationContext as PiyakApplication).repository
        repo.scope.launch {
            try { repo.refresh(); updateAll(context, repo.snapshot(), repo.clock()) }
            catch (_: Exception) { ids.forEach { manager.updateAppWidget(it, RemoteViews(context.packageName, R.layout.widget_bank).apply { setTextViewText(R.id.widget_status, "앱에서 기록을 확인해 주세요") }) } }
            finally { pending.finish() }
        }
    }
    companion object {
        fun updateAll(context: Context, state: PersistentState, now: ClockSample) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, PiyakWidget::class.java))
            if (ids.isEmpty()) return
            val data = DomainEngine.projectActive(state.data, now)
            val zone = ZoneId.systemDefault()
            val date = Instant.ofEpochMilli(now.wallMillis).atZone(zone).toLocalDate()
            val total = (data.records.map { it.segments } + listOfNotNull(data.active?.segments)).sumOf { EarningsCalculator.earnedOn(it, date, now.wallMillis, zone) }
            val click = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val view = RemoteViews(context.packageName, R.layout.widget_bank).apply {
                setTextViewText(R.id.widget_amount, "${NumberFormat.getIntegerInstance(Locale.KOREA).format(total)}원")
                setTextViewText(R.id.widget_status, when { !state.settings.onboarded -> "눌러서 시작해요"; data.active == null -> "오늘의 예상 수익"; data.active?.tracking?.working == true -> "삐약이와 근무 중"; else -> "잠시 쉬는 중" })
                val time = Instant.ofEpochMilli(now.wallMillis).atZone(zone).format(DateTimeFormatter.ofPattern("HH:mm"))
                setTextViewText(R.id.widget_time, "$time 기준 · 눌러서 최신 기록 확인")
                setTextViewText(R.id.widget_points, "${DomainEngine.balance(data)} P")
                setOnClickPendingIntent(R.id.widget_root, click)
            }
            manager.updateAppWidget(ids, view)
        }
    }
}
