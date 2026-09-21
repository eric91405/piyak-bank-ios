package com.minseo.piyakbank.ui

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.minseo.piyakbank.core.*
import com.minseo.piyakbank.platform.UiState
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

internal fun Long.commas(): String = NumberFormat.getIntegerInstance(Locale.KOREA).format(this)
internal fun Int.commas(): String = toLong().commas()
internal fun Long.won(): String = "${commas()}원"
internal fun Long.points(): String = "${commas()} P"
internal val KoreanDate: DateTimeFormatter = DateTimeFormatter.ofPattern("M월 d일 EEEE", Locale.KOREAN)
internal val RecordTime: DateTimeFormatter = DateTimeFormatter.ofPattern("M.d (E) HH:mm", Locale.KOREAN)
internal fun displayTime(millis: Long): String = Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).format(RecordTime)
internal fun paidTime(segments: List<Segment>, now: Long): String {
    val seconds = EarningsCalculator.workingMillis(segments, now) / 1000
    return "${seconds / 3600}시간 ${seconds % 3600 / 60}분 ${seconds % 60}초"
}

/** Work is bounded by the visible month, even for a timer left running for years. */
internal fun monthAmounts(records: List<List<Segment>>, month: YearMonth, now: Long, zone: ZoneId): Map<LocalDate, Long> {
    val result = mutableMapOf<LocalDate, Long>()
    val start = month.atDay(1).atStartOfDay(zone).toInstant().toEpochMilli()
    val end = month.plusMonths(1).atDay(1).atStartOfDay(zone).toInstant().toEpochMilli()
    records.filter { segments -> segments.any { it.hourlyWage > 0 && it.startMillis < end && minOf(it.endMillis ?: now, now) > start } }.forEach { segments ->
        // Round each record independently and preserve its fractional carry from earlier days.
        for (dayNumber in 1..month.lengthOfMonth()) {
            val day = month.atDay(dayNumber)
            val amount = EarningsCalculator.earnedOn(segments, day, now, zone)
            if (amount != 0L) result[day] = (result[day] ?: 0L) + amount
        }
    }
    return result
}

@Composable
internal fun GameCard(
    modifier: Modifier = Modifier,
    color: Color = MaterialTheme.colorScheme.surface,
    content: @Composable ColumnScope.() -> Unit,
) {
    Surface(modifier = modifier.fillMaxWidth(), color = color, shape = RoundedCornerShape(26.dp), tonalElevation = 1.dp) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
    }
}

@Composable
internal fun ScreenHeading(title: String, subtitle: String? = null, trailing: (@Composable () -> Unit)? = null) {
    val fontScale = LocalDensity.current.fontScale
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        if (maxWidth < 380.dp && fontScale > 1.2f) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(title, style = MaterialTheme.typography.headlineMedium)
                trailing?.invoke()
            }
        } else Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(title, style = MaterialTheme.typography.headlineMedium)
            }
            trailing?.invoke()
        }
    }
}

@Composable
internal fun PointBadge(balance: Long) {
    Surface(color = MaterialTheme.colorScheme.primaryContainer, shape = RoundedCornerShape(50), modifier = Modifier.semantics { contentDescription = "보유 포인트 ${balance.commas()}" }) {
        Row(Modifier.padding(horizontal = 13.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            Icon(Icons.Rounded.Stars, null, Modifier.size(19.dp))
            Text(balance.points(), style = MaterialTheme.typography.labelLarge)
        }
    }
}

@Composable
internal fun InfoText(text: String, icon: ImageVector = Icons.Rounded.Info) {
    Row(horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = androidx.compose.ui.Alignment.Top) {
        Icon(icon, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
internal fun ErrorText(text: String?) {
    if (text != null) Text(text, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.fillMaxWidth().semantics { contentDescription = "오류: $text" })
}

@Composable
internal fun ActionCompletion(ui: UiState, submittedAt: Long?, onComplete: () -> Unit) {
    LaunchedEffect(ui.actionRevision, submittedAt) {
        if (submittedAt != null && ui.actionRevision > submittedAt) onComplete()
    }
}

@Composable
internal fun ItemThumbnail(id: String, name: String, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val bitmap: ImageBitmap? = remember(id) {
        runCatching {
            context.assets.open("thumbs/${id.replace('.', '_')}.png").use { BitmapFactory.decodeStream(it)?.asImageBitmap() }
        }.getOrNull()
    }
    Box(modifier.background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(18.dp)), contentAlignment = androidx.compose.ui.Alignment.Center) {
        if (bitmap != null) Image(bitmap, contentDescription = name, modifier = Modifier.fillMaxSize().padding(8.dp), contentScale = ContentScale.Fit)
        else Icon(Icons.Rounded.AutoAwesome, name, Modifier.size(42.dp), tint = MaterialTheme.colorScheme.secondary)
    }
}

internal fun slotIcon(slot: DecorSlot): ImageVector = when (slot) {
    DecorSlot.bg -> Icons.Rounded.Wallpaper
    DecorSlot.wallDeco -> Icons.Rounded.Photo
    DecorSlot.bigFurniture -> Icons.Rounded.Chair
    DecorSlot.floorProp -> Icons.Rounded.LocalFlorist
    DecorSlot.rug -> Icons.Rounded.Layers
    DecorSlot.headTop -> Icons.Rounded.Face
    DecorSlot.eyes -> Icons.Rounded.Visibility
    DecorSlot.headband -> Icons.Rounded.AutoAwesome
    DecorSlot.neck -> Icons.Rounded.Favorite
    DecorSlot.bodyFront -> Icons.Rounded.Checkroom
}
