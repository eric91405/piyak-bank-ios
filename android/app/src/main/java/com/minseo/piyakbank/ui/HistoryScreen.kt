package com.minseo.piyakbank.ui

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.Context
import android.text.format.DateFormat
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import com.minseo.piyakbank.core.*
import com.minseo.piyakbank.platform.PiyakViewModel
import com.minseo.piyakbank.platform.UiState
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.util.UUID

@Composable
internal fun HistoryScreen(ui: UiState, viewModel: PiyakViewModel) {
    val data = ui.data ?: return
    val zone = ZoneId.systemDefault()
    val today = Instant.ofEpochMilli(ui.now).atZone(zone).toLocalDate()
    var selectedDay by rememberSaveable { mutableStateOf(today.toString()) }
    val day = LocalDate.parse(selectedDay)
    val month = YearMonth.from(day)
    var editor by rememberSaveable { mutableStateOf<String?>(null) }
    var deleting by rememberSaveable { mutableStateOf<String?>(null) }
    var submittedAt by rememberSaveable { mutableStateOf<Long?>(null) }
    val completedAmounts = remember(data.records, month, today, zone) { monthAmounts(data.records.map { it.segments }, month, ui.now, zone) }
    val amounts = completedAmounts.toMutableMap()
    data.active?.let { monthAmounts(listOf(it.segments), month, ui.now, zone).forEach { (day, amount) -> amounts[day] = (amounts[day] ?: 0L) + amount } }
    val monthAmount = amounts.values.sum()
    val start = day.atStartOfDay(zone).toInstant().toEpochMilli()
    val end = day.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
    val dayRecords = remember(data.records, day, zone) { data.records.filter { record -> record.segments.any { it.startMillis < end && (it.endMillis ?: ui.now) > start } }.sortedByDescending { it.segments.firstOrNull()?.startMillis } }
    val active = data.active?.takeIf { it.segments.any { segment -> segment.startMillis < end && (segment.endMillis ?: ui.now) > start } }
    ActionCompletion(ui, submittedAt) { deleting = null; submittedAt = null }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        LazyColumn(Modifier.widthIn(max = 780.dp).fillMaxSize(), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            item { ScreenHeading("차곡차곡 기록", "내 시간의 가치를 한눈에") {
                IconButton(onClick = { editor = "new:${UUID.randomUUID()}" }, enabled = !ui.busy) { Icon(Icons.Rounded.Add, "놓친 근무 추가") }
            } }
            item { GameCard(color = MaterialTheme.colorScheme.tertiaryContainer) {
                Text("${month.year}년 ${month.monthValue}월", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onTertiaryContainer)
                Text(monthAmount.won(), style = MaterialTheme.typography.displaySmall, color = MaterialTheme.colorScheme.onTertiaryContainer)
                Text("선택한 달의 예상 수익 · 진행 중인 근무 포함", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onTertiaryContainer)
            } }
            item { EarningsCalendar(day, today, amounts, onSelect = { selectedDay = it.toString() }) }
            item {
                Text(day.format(KoreanDate), style = MaterialTheme.typography.titleLarge)
                Text("${dayRecords.size + if (active != null) 1 else 0}개의 근무 · ${(amounts[day] ?: 0L).won()}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (active != null) item(key = "active") {
                RecordCard(WorkRecord(active.id, active.segments), day, zone, ui.now, true, null, null)
            }
            items(dayRecords, key = { it.id }) { record ->
                RecordCard(record, day, zone, ui.now, false, { editor = record.snapshot() }, { deleting = record.snapshot() })
            }
            if (dayRecords.isEmpty() && active == null) item {
                GameCard {
                    Icon(Icons.Rounded.CalendarToday, null, Modifier.size(36.dp), tint = MaterialTheme.colorScheme.secondary)
                    Text("아직 조용한 하루예요", style = MaterialTheme.typography.titleMedium)
                    Text("놓친 근무가 있으면 직접 기록해 보세요. 기록에는 예상 수익만 반영돼요.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    OutlinedButton(onClick = { editor = "new:${UUID.randomUUID()}" }, enabled = !ui.busy) { Icon(Icons.Rounded.Add, null); Spacer(Modifier.width(5.dp)); Text("근무 기록 추가") }
                }
            }
            item { InfoText("예상 수익과 날짜는 기기의 시간대를 사용해요. 꾸미기 보상 한도는 한국 시간 기준이며, 수동 기록으로 포인트가 늘어나지 않아요.") }
        }
    }
    editor?.let { payload ->
        key(payload) { RecordEditor(if (payload.startsWith("new:")) null else recordFromSnapshot(payload), ui, viewModel, onDismiss = { editor = null }) }
    }
    deleting?.let { payload ->
        val record = remember(payload) { recordFromSnapshot(payload) }
        DensityAwareAlertDialog(
            onDismissRequest = { if (!ui.busy) { deleting = null; submittedAt = null } },
            title = { Text("이 기록을 삭제할까요?") },
            text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("근무 시간과 예상 수익을 삭제해요. 이미 받은 포인트와 레벨은 유지되며, 기록을 다시 추가해도 포인트는 늘지 않아요.")
                Text("삭제는 되돌릴 수 없어요.", color = MaterialTheme.colorScheme.error)
                ErrorText(ui.error)
            } },
            confirmButton = { TextButton(onClick = { submittedAt = ui.actionRevision; viewModel.deleteRecord(record.id, record.revision) }, enabled = !ui.busy) { Text("기록 삭제", color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton(onClick = { deleting = null; submittedAt = null }, enabled = !ui.busy) { Text("취소") } },
        )
    }
}

@Composable
private fun EarningsCalendar(day: LocalDate, today: LocalDate, amounts: Map<LocalDate, Long>, onSelect: (LocalDate) -> Unit) {
    val month = YearMonth.from(day)
    val offset = month.atDay(1).dayOfWeek.value % 7
    val rows = (offset + month.lengthOfMonth() + 6) / 7
    val fontScale = LocalDensity.current.fontScale
    GameCard {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { onSelect(month.minusMonths(1).atDay(1)) }) { Icon(Icons.Rounded.ChevronLeft, "이전 달") }
            Text("${month.year}년 ${month.monthValue}월", modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center, style = MaterialTheme.typography.titleMedium)
            IconButton(onClick = { onSelect(month.plusMonths(1).atDay(1)) }) { Icon(Icons.Rounded.ChevronRight, "다음 달") }
        }
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            // Each day keeps a 48dp touch area after its two 1dp spacing insets.
            val width = maxOf(maxWidth, (50 * fontScale.coerceAtLeast(1f) * 7).dp)
            Column(Modifier.horizontalScroll(rememberScrollState()).width(width), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row { listOf("일", "월", "화", "수", "목", "금", "토").forEach { Text(it, Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
                repeat(rows) { row -> Row {
                    repeat(7) { column ->
                        val value = row * 7 + column - offset + 1
                        if (value !in 1..month.lengthOfMonth()) Spacer(Modifier.weight(1f).height(65.dp))
                        else {
                            val date = month.atDay(value)
                            val amount = amounts[date] ?: 0L
                            Surface(modifier = Modifier.weight(1f).padding(1.dp).selectable(selected = date == day, onClick = { onSelect(date) }, role = Role.Button).semantics { contentDescription = "${date.year}년 ${date.format(KoreanDate)}, 예상 수익 ${amount.won()}${if (date == today) ", 오늘" else ""}" }, shape = RoundedCornerShape(13.dp), color = if (date == day) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface) {
                                Column(Modifier.heightIn(min = 65.dp).padding(vertical = 7.dp, horizontal = 1.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
                                    Text(if (date == today) "$value·" else "$value", style = MaterialTheme.typography.labelLarge)
                                    Text(if (amount == 0L) "—" else compactAmount(amount), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                } }
            }
        }
        TextButton(onClick = { onSelect(today) }, modifier = Modifier.align(Alignment.End)) { Text("오늘로") }
    }
}

private fun compactAmount(amount: Long): String = when {
    amount >= 100_000_000 -> String.format(java.util.Locale.KOREA, "%.1f억", amount / 100_000_000.0)
    amount >= 10_000 -> String.format(java.util.Locale.KOREA, "%.1f만", amount / 10_000.0)
    else -> amount.commas()
}

@Composable
private fun RecordCard(record: WorkRecord, day: LocalDate, zone: ZoneId, now: Long, active: Boolean, edit: (() -> Unit)?, delete: (() -> Unit)?) {
    var menu by remember { mutableStateOf(false) }
    val amount = EarningsCalculator.earnedOn(record.segments, day, now, zone)
    GameCard {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Icon(if (active) Icons.Rounded.Schedule else Icons.Rounded.TaskAlt, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(8.dp))
            Text(if (active) "진행 중인 근무" else "마친 근무", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            if (!active) Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Rounded.MoreHoriz, "근무 기록 수정 또는 삭제") }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text("기록 수정") }, leadingIcon = { Icon(Icons.Rounded.Edit, null) }, onClick = { menu = false; edit?.invoke() })
                    DropdownMenuItem(text = { Text("기록 삭제") }, leadingIcon = { Icon(Icons.Rounded.DeleteOutline, null) }, onClick = { menu = false; delete?.invoke() })
                }
            }
        }
        Text(amount.won(), style = MaterialTheme.typography.headlineMedium)
        Text("선택한 날짜에 해당하는 예상 수익", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        record.segments.firstOrNull()?.let { Text("${displayTime(it.startMillis)} → ${record.segments.last().endMillis?.let(::displayTime) ?: "지금"}", style = MaterialTheme.typography.bodySmall) }
        Text("유급 ${paidTime(record.segments, now)} · 휴식 제외", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private data class SegmentDraft(val start: Long, val end: Long, val wage: String)
private val DraftSaver = listSaver<List<SegmentDraft>, String>(save = { drafts -> drafts.map { "${it.start}|${it.end}|${it.wage}" } }, restore = { values -> values.map { val parts = it.split('|'); SegmentDraft(parts[0].toLong(), parts[1].toLong(), parts.getOrElse(2) { "" }) } })

@Composable
private fun RecordEditor(record: WorkRecord?, ui: UiState, viewModel: PiyakViewModel, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var drafts by rememberSaveable(stateSaver = DraftSaver) { mutableStateOf(record?.segments?.map { SegmentDraft(it.startMillis, it.endMillis ?: ui.now, it.hourlyWage.toString()) } ?: listOf(SegmentDraft(ui.now - 3_600_000, ui.now, ui.settings.wage.toString()))) }
    var confirm by rememberSaveable { mutableStateOf(false) }
    var discard by rememberSaveable { mutableStateOf(false) }
    var changed by rememberSaveable { mutableStateOf(false) }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    var submittedAt by rememberSaveable { mutableStateOf<Long?>(null) }
    ActionCompletion(ui, submittedAt) { onDismiss() }
    fun update(index: Int, value: SegmentDraft) { drafts = drafts.toMutableList().also { it[index] = value }; changed = true; error = null }
    fun requestDismiss() { if (!ui.busy) { if (changed) discard = true else onDismiss() } }
    DensityAwareDialog(onDismissRequest = ::requestDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(modifier = Modifier.padding(12.dp).widthIn(max = 720.dp).fillMaxWidth().fillMaxHeight(.96f).imePadding(), shape = RoundedCornerShape(28.dp), color = MaterialTheme.colorScheme.background) {
            Column {
                Row(Modifier.fillMaxWidth().padding(start = 8.dp, end = 12.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = ::requestDismiss, enabled = !ui.busy) { Icon(Icons.Rounded.Close, "편집 취소") }
                    Text(if (record == null) "놓친 근무 추가" else "근무 기록 수정", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                }
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    InfoText("근무와 휴식을 시간 구간으로 나눠 입력해요. 휴식 구간의 시급은 0원이에요. 날짜가 바뀌어도 자동으로 나눠 계산해요.")
                    InfoText("예상 수익만 변경돼요. 포인트와 레벨은 늘어나거나 줄어들지 않아요.", Icons.Rounded.Stars)
                    drafts.forEachIndexed { index, draft ->
                        GameCard {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text("${index + 1}. ${if (draft.wage == "0") "휴식 구간" else "근무 구간"}", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                                if (drafts.size > 1) IconButton(onClick = { drafts = drafts.filterIndexed { position, _ -> position != index }; changed = true }, enabled = !ui.busy) { Icon(Icons.Rounded.DeleteOutline, "${index + 1}번째 구간 삭제") }
                            }
                            OutlinedButton(onClick = { pickDateTime(context, draft.start) { update(index, draft.copy(start = it)) } }, enabled = !ui.busy, modifier = Modifier.fillMaxWidth(), contentPadding = PaddingValues(14.dp)) {
                                Column(Modifier.fillMaxWidth()) { Text("시작", style = MaterialTheme.typography.bodySmall); Text(displayTime(draft.start)) }
                            }
                            OutlinedButton(onClick = { pickDateTime(context, draft.end) { update(index, draft.copy(end = it)) } }, enabled = !ui.busy, modifier = Modifier.fillMaxWidth(), contentPadding = PaddingValues(14.dp)) {
                                Column(Modifier.fillMaxWidth()) { Text("종료", style = MaterialTheme.typography.bodySmall); Text(displayTime(draft.end)) }
                            }
                            OutlinedTextField(value = draft.wage, onValueChange = { update(index, draft.copy(wage = it.filter(Char::isDigit).take(8))) }, enabled = !ui.busy, label = { Text("${index + 1}번째 구간 시급") }, suffix = { Text("원") }, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.fillMaxWidth(), supportingText = { Text("0원은 휴식 · 최대 1,000,000원") }, isError = draft.wage.toIntOrNull()?.let { it !in 0..1_000_000 } ?: true)
                        }
                    }
                    OutlinedButton(onClick = { val previous = drafts.last().end; drafts = drafts + SegmentDraft(previous, maxOf(previous, ui.now), "0"); changed = true }, enabled = !ui.busy && drafts.size < 100, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Rounded.Add, null); Spacer(Modifier.width(6.dp)); Text("근무·휴식 구간 추가") }
                    InfoText("구간은 겹칠 수 없고 한 기록은 최대 7일이에요. 시간은 이 기기의 시간대를 사용해요. 시작과 종료가 같으면 저장할 수 없어요.")
                    ErrorText(error ?: ui.error)
                }
                Surface(color = MaterialTheme.colorScheme.surface, shadowElevation = 3.dp) {
                    Button(onClick = { error = validateDrafts(drafts, System.currentTimeMillis()); if (error == null) confirm = true }, enabled = !ui.busy, modifier = Modifier.fillMaxWidth().padding(18.dp).heightIn(min = 52.dp)) { Text(if (ui.busy) "저장 중" else "기록 저장") }
                }
            }
        }
    }
    if (confirm) DensityAwareAlertDialog(
        onDismissRequest = { if (!ui.busy) confirm = false }, title = { Text("근무 기록을 저장할까요?") },
        text = { Text("근무 시간과 예상 수익에 반영돼요. 이미 받은 포인트와 레벨은 그대로 유지돼요.") },
        confirmButton = { Button(onClick = {
            error = validateDrafts(drafts, System.currentTimeMillis())
            if (error == null) {
                submittedAt = ui.actionRevision
                val segments = drafts.map { Segment(it.start, it.end, it.wage.toInt()) }.sortedBy { it.startMillis }
                if (record == null) viewModel.addRecord(segments) else viewModel.editRecord(record.id, record.revision, segments)
            }
            confirm = false
        }, enabled = !ui.busy) { Text("저장") } },
        dismissButton = { TextButton(onClick = { confirm = false }, enabled = !ui.busy) { Text("계속 편집") } },
    )
    if (discard) DensityAwareAlertDialog(onDismissRequest = { discard = false }, title = { Text("작성한 내용을 닫을까요?") }, text = { Text("저장하지 않은 수정 내용은 사라져요.") }, confirmButton = { TextButton(onClick = onDismiss) { Text("저장하지 않고 닫기") } }, dismissButton = { TextButton(onClick = { discard = false }) { Text("계속 편집") } })
}

private fun validateDrafts(drafts: List<SegmentDraft>, now: Long): String? {
    if (drafts.isEmpty()) return "근무 구간을 하나 이상 추가해 주세요."
    if (drafts.any { it.wage.toIntOrNull()?.let { wage -> wage !in 0..1_000_000 } ?: true }) return "시급은 0~1,000,000원으로 입력해 주세요."
    if (drafts.any { it.start >= it.end }) return "각 구간의 종료는 시작보다 늦어야 해요."
    if (drafts.any { it.end > now }) return "미래의 근무는 기록할 수 없어요. 종료 시간을 확인해 주세요."
    val sorted = drafts.sortedBy { it.start }
    if (sorted.zipWithNext().any { (a, b) -> a.end > b.start }) return "시간 구간이 겹쳐요. 시작과 종료를 확인해 주세요."
    if (sorted.last().end - sorted.first().start > 7 * 86_400_000L) return "한 근무 기록은 최대 7일이에요. 나누어 기록해 주세요."
    return null
}

private fun pickDateTime(context: Context, millis: Long, onSelected: (Long) -> Unit) {
    val zone = ZoneId.systemDefault()
    val time = Instant.ofEpochMilli(millis).atZone(zone)
    val picker = DatePickerDialog(context, { _, year, month, day ->
        TimePickerDialog(context, { _, hour, minute ->
            onSelected(LocalDate.of(year, month + 1, day).atTime(hour, minute).atZone(zone).toInstant().toEpochMilli())
        }, time.hour, time.minute, DateFormat.is24HourFormat(context)).show()
    }, time.year, time.monthValue - 1, time.dayOfMonth)
    picker.datePicker.maxDate = System.currentTimeMillis()
    picker.show()
}

/** The sheet owns a value snapshot, never a live lookup that could silently replace its revision. */
private fun WorkRecord.snapshot(): String = JSONObject().put("id", id).put("revision", revision).put("segments", JSONArray().apply { segments.forEach { put(JSONObject().put("start", it.startMillis).put("end", it.endMillis).put("wage", it.hourlyWage)) } }).toString()
private fun recordFromSnapshot(value: String): WorkRecord = JSONObject(value).let { json ->
    val segments = json.getJSONArray("segments")
    WorkRecord(json.getString("id"), (0 until segments.length()).map { index -> segments.getJSONObject(index).let { Segment(it.getLong("start"), if (it.isNull("end")) null else it.getLong("end"), it.getInt("wage")) } }, json.getLong("revision"))
}
