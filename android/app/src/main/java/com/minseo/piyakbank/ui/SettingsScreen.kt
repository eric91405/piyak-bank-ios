package com.minseo.piyakbank.ui

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.app.NotificationManagerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.minseo.piyakbank.core.DomainEngine
import com.minseo.piyakbank.platform.PiyakViewModel
import com.minseo.piyakbank.platform.UiState

@Composable
internal fun SettingsScreen(ui: UiState, viewModel: PiyakViewModel, onExport: (String) -> Unit, onRequestNotifications: () -> Unit) {
    val data = ui.data ?: return
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    var wage by rememberSaveable { mutableStateOf(false) }
    var reset by rememberSaveable { mutableStateOf(false) }
    var page by rememberSaveable { mutableStateOf<String?>(null) }
    var linkError by rememberSaveable { mutableStateOf<String?>(null) }
    var intervalMenu by remember { mutableStateOf(false) }
    var systemNotifications by remember { mutableStateOf(NotificationManagerCompat.from(context).areNotificationsEnabled()) }
    DisposableEffect(owner, context) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_RESUME) systemNotifications = NotificationManagerCompat.from(context).areNotificationsEnabled() }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(ui.settings.notificationsEnabled) { systemNotifications = NotificationManagerCompat.from(context).areNotificationsEnabled() }
    fun open(intent: Intent) { runCatching { context.startActivity(intent) }.onFailure { linkError = "이 링크를 열 수 있는 앱이 없어요. 지원 이메일은 eric91405@gmail.com이에요." } }
    val version = remember(context) { runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "1.0" }.getOrDefault("1.0") }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Column(Modifier.widthIn(max = 780.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            ScreenHeading("나와 삐약이", "우리의 일상을 내 방식대로")
            GameCard(color = MaterialTheme.colorScheme.secondaryContainer) {
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.EggAlt, null, Modifier.size(56.dp), tint = MaterialTheme.colorScheme.onSecondaryContainer)
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("조금씩, 함께 자라는 중", style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.onSecondaryContainer)
                        Text("Lv. ${DomainEngine.level(data)} · 완료한 근무 ${data.records.size}회", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSecondaryContainer)
                    }
                }
            }
            SettingsGroup("근무와 우리 방") {
                SettingLink(Icons.Rounded.Payments, "기본 시급", ui.settings.wage.toLong().won(), enabled = !ui.busy && data.active == null) { wage = true }
                InfoText(if (data.active == null) "다음 근무의 예상 수익에 적용돼요. 시급은 꾸미기 포인트에 영향을 주지 않아요." else "진행 중인 근무는 시급을 바꿀 수 없어요. 종료 후 기록에서 수정할 수 있어요.")
                HorizontalDivider()
                SettingToggle(Icons.Rounded.Animation, "삐약이 움직임", "움직임을 줄이면 배터리 사용도 줄어들어요", ui.settings.animationEnabled, !ui.busy) { viewModel.updateAnimation(it) }
            }
            SettingsGroup("꾸미기 보상") {
                SettingValue("타이머 근무", "10분에 100P")
                SettingValue("하루 적립 한도", "4,800 P")
                SettingValue("하루 기준", "한국 시간 00시")
                InfoText("시급과 무관하며 휴식은 제외해요. 기록을 직접 추가·수정해도 보상이 늘지 않고, 이미 받은 포인트와 레벨은 기록을 수정·삭제해도 유지돼요.")
                InfoText("한 타이머의 보상은 누적 유급 24시간까지예요. 그 뒤에도 예상 수익은 계속 기록돼요. 근무를 마치고 다시 시작해도 하루 한도는 유지돼요.")
            }
            SettingsGroup("알림") {
                SettingToggle(Icons.Rounded.NotificationsActive, "근무 중 알림", "근무를 잊지 않도록 가끔 알려 드려요", ui.settings.notificationsEnabled, !ui.busy) {
                    if (it) onRequestNotifications() else viewModel.updateNotifications(false)
                }
                Box {
                    SettingLink(Icons.Rounded.Timer, "알림 간격", "${ui.settings.reminderMinutes}분", enabled = ui.settings.notificationsEnabled && !ui.busy) { intervalMenu = true }
                    DropdownMenu(expanded = intervalMenu, onDismissRequest = { intervalMenu = false }) {
                        listOf(15, 30, 60, 120).forEach { minutes -> DropdownMenuItem(text = { Text("${minutes}분") }, onClick = { intervalMenu = false; viewModel.updateReminderMinutes(minutes) }, trailingIcon = if (ui.settings.reminderMinutes == minutes) ({ Icon(Icons.Rounded.Check, null) }) else null) }
                    }
                }
                SettingValue("시스템 알림 권한", if (systemNotifications) "허용됨" else "꺼져 있음")
                TextButton(onClick = { open(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)) }) { Text("시스템 알림 설정 열기") }
                InfoText("배터리 절약, 방해 금지, 제조사 설정에 따라 알림이 늦거나 표시되지 않을 수 있어요. 알림 도착 여부와 관계없이 근무 기록은 유지돼요.")
            }
            SettingsGroup("위젯과 Wear OS") {
                SettingLink(Icons.Rounded.Widgets, "홈 화면 위젯", "오늘 수익을 빠르게 확인") { page = "widget" }
                SettingLink(Icons.Rounded.Watch, "시계에서 함께하기", "휴대폰과 연결된 Wear OS") { page = "watch" }
            }
            SettingsGroup("내 데이터") {
                SettingLink(Icons.Rounded.FileDownload, "근무 기록 CSV 내보내기", "시간·시급·예상 수익", enabled = !ui.busy) { onExport("records") }
                SettingLink(Icons.Rounded.ReceiptLong, "포인트 원장 CSV 내보내기", "적립·사용 내역", enabled = !ui.busy) { onExport("points") }
                InfoText("CSV는 보관용이에요. 앱으로 다시 불러오는 복원 기능은 없어요. 파일을 공유하면 안의 근무 정보도 함께 전달돼요.")
                TextButton(onClick = { reset = true }, enabled = !ui.busy) { Icon(Icons.Rounded.DeleteForever, null, tint = MaterialTheme.colorScheme.error); Spacer(Modifier.width(8.dp)); Text("모든 데이터 초기화", color = MaterialTheme.colorScheme.error) }
            }
            SettingsGroup("도움말과 개인정보") {
                SettingLink(Icons.Rounded.HelpOutline, "삐약뱅크 이용 안내", null) { page = "help" }
                SettingLink(Icons.Rounded.PrivacyTip, "개인정보 처리방침", null) { page = "privacy" }
                SettingLink(Icons.Rounded.MailOutline, "지원 문의", "eric91405@gmail.com") { open(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:eric91405@gmail.com?subject=${Uri.encode("삐약뱅크 Android 문의 (v$version)")}"))) }
                SettingValue("운영자", "김민서")
                SettingValue("버전", version)
            }
            Text("오늘도 함께해 줘서 고마워요.\n당신의 시간을 응원하는 삐약뱅크", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 12.dp))
        }
    }
    if (wage) WageDialog(ui, viewModel, onDismiss = { wage = false })
    if (reset) ResetDialog(ui, viewModel, onDismiss = { reset = false })
    if (page != null) HelpPage(page!!, onDismiss = { page = null }, openPrivacy = { open(Intent(Intent.ACTION_VIEW, Uri.parse("https://eric91405.github.io/piyak-bank-ios/privacy-android/"))) })
    if (linkError != null) AlertDialog(onDismissRequest = { linkError = null }, title = { Text("연결 앱을 확인해 주세요") }, text = { Text(linkError!!) }, confirmButton = { TextButton(onClick = { linkError = null }) { Text("확인") } })
}

@Composable
private fun SettingsGroup(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 5.dp))
        GameCard(content = content)
    }
}

@Composable
private fun SettingValue(title: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Text(value, style = MaterialTheme.typography.labelLarge, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.End)
    }
}

@Composable
private fun SettingLink(icon: ImageVector, title: String, detail: String?, enabled: Boolean = true, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick).heightIn(min = 56.dp).padding(vertical = 7.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, null, tint = if (enabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
            if (detail != null) Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Icon(Icons.Rounded.ChevronRight, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun SettingToggle(icon: ImageVector, title: String, detail: String, checked: Boolean, enabled: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Switch(checked, onChange, enabled = enabled, modifier = Modifier.semantics { contentDescription = title })
    }
}

@Composable
private fun WageDialog(ui: UiState, viewModel: PiyakViewModel, onDismiss: () -> Unit) {
    var value by rememberSaveable { mutableStateOf(ui.settings.wage.toString()) }
    var submittedAt by rememberSaveable { mutableStateOf<Long?>(null) }
    val valid = value.toIntOrNull()?.let { it in 1..1_000_000 } == true
    ActionCompletion(ui, submittedAt, onDismiss)
    AlertDialog(onDismissRequest = { if (!ui.busy) onDismiss() }, title = { Text("기본 시급") }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            OutlinedTextField(value, { value = it.filter(Char::isDigit).take(8) }, label = { Text("시급") }, suffix = { Text("원") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true, enabled = !ui.busy, isError = !valid, modifier = Modifier.fillMaxWidth())
            Text("1~1,000,000원 · 다음 근무부터 적용돼요. 꾸미기 포인트에는 영향을 주지 않아요.", style = MaterialTheme.typography.bodySmall)
            ErrorText(ui.error)
        }
    }, confirmButton = { Button(onClick = { submittedAt = ui.actionRevision; viewModel.updateWage(value.toInt()) }, enabled = valid && !ui.busy && ui.data?.active == null) { Text("저장") } }, dismissButton = { TextButton(onClick = onDismiss, enabled = !ui.busy) { Text("취소") } })
}

@Composable
private fun ResetDialog(ui: UiState, viewModel: PiyakViewModel, onDismiss: () -> Unit) {
    var confirm by rememberSaveable { mutableStateOf("") }
    var submittedAt by rememberSaveable { mutableStateOf<Long?>(null) }
    ActionCompletion(ui, submittedAt, onDismiss)
    AlertDialog(onDismissRequest = { if (!ui.busy) onDismiss() }, icon = { Icon(Icons.Rounded.DeleteForever, null, tint = MaterialTheme.colorScheme.error) }, title = { Text("모든 데이터를 지울까요?") }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("진행 중인 근무, 저장한 기록, 포인트, 구매한 아이템을 지우고 기본 방으로 돌아가요. 되돌릴 수 없으니 필요한 기록은 먼저 CSV로 내보내 주세요.")
            Text("확인하려면 아래에 ‘초기화’를 입력해 주세요.", style = MaterialTheme.typography.bodyMedium)
            OutlinedTextField(confirm, { confirm = it }, label = { Text("초기화") }, singleLine = true, modifier = Modifier.fillMaxWidth(), enabled = !ui.busy)
            ErrorText(ui.error)
        }
    }, confirmButton = { Button(onClick = { submittedAt = ui.actionRevision; viewModel.reset() }, enabled = confirm == "초기화" && !ui.busy, colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)) { Text("모든 데이터 삭제") } }, dismissButton = { TextButton(onClick = onDismiss, enabled = !ui.busy) { Text("취소") } })
}

@Composable
private fun HelpPage(page: String, onDismiss: () -> Unit, openPrivacy: () -> Unit) {
    val title = when (page) { "privacy" -> "개인정보 처리방침"; "widget" -> "홈 화면 위젯"; "watch" -> "Wear OS에서 함께하기"; else -> "삐약뱅크 이용 안내" }
    val paragraphs = when (page) {
        "privacy" -> listOf(
            "기기에 보관하는 기록" to "시급, 근무 구간, 예상 수익, 꾸미기 포인트와 아이템, 앱 설정을 이 기기에 저장해요. 회원 가입과 로그인은 없어요.",
            "연결된 시계와 동기화" to "연결된 Android 휴대폰과 Wear OS 시계 사이에 근무 상태, 오늘의 예상 수익, 포인트 잔액과 장착 정보를 동기화해요. 시계의 근무 시작·휴식·종료 요청은 휴대폰이 확인하고 저장해요.",
            "암호화된 기기 간 전달" to "기기 간 통신에는 Google Play services의 Wear Data Layer를 사용해요. Bluetooth를 사용할 수 없는 등의 상황에서는 Google의 클라우드를 통한 종단 간 암호화 중계를 사용할 수 있어요. 따라서 동기화 정보가 항상 기기 안에만 머무르는 것은 아니에요.",
            "개발자 서버·광고·분석" to "근무 기록을 개발자 서버로 보내지 않아요. 광고 또는 이용 행태 분석을 위한 전송과 SDK, AI 대화 기능은 없어요. Google Play services는 연결된 시계와 정보를 전달하는 데 사용해요.",
            "알림과 파일" to "알림은 사용자가 허용한 경우에 표시돼요. CSV 내보내기는 사용자가 선택한 위치에 파일을 저장해요. 저장하거나 공유한 파일은 사용자가 관리해 주세요.",
            "삭제와 문의" to "설정의 모든 데이터 초기화로 기기의 앱 데이터를 삭제할 수 있어요. 앱을 삭제하면 기록을 복원할 수 없어요. 지원 문의: eric91405@gmail.com · 운영자: 김민서",
        )
        "widget" -> listOf(
            "홈 화면에 놓기" to "휴대폰 홈 화면의 빈 곳을 길게 누르고 위젯에서 삐약뱅크를 찾아 추가해 주세요. 기기나 런처에 따라 메뉴 이름이 다를 수 있어요.",
            "한눈에 보는 오늘" to "오늘의 예상 수익과 최근 근무 상태를 표시해요. 위젯을 누르면 앱에서 최신 정보를 확인할 수 있어요.",
            "갱신 시간" to "위젯은 앱에서 근무 상태가 바뀔 때와 Android가 허용한 주기에 갱신돼요. 초 단위로 움직이지 않으며, 절전 상태에서는 표시가 늦을 수 있어요. 정확한 현재 수익은 앱에서 확인해 주세요.",
        )
        "watch" -> listOf(
            "휴대폰과 연결해 주세요" to "호환되는 Wear OS 시계를 Android 휴대폰과 연결하고 시계에도 삐약뱅크를 설치해 주세요. 휴대폰에서 첫 설정을 끝내면 근무 정보를 확인할 수 있어요.",
            "손목에서 근무 관리" to "연결된 시계에서 현재 근무를 확인하고 시작, 휴식, 재개, 종료를 요청할 수 있어요. 근무와 포인트의 원본은 휴대폰에 보관돼요.",
            "연결이 끊겼을 때" to "연결되지 않았을 때는 표시가 최신이 아닐 수 있어요. 시계에 표시된 갱신 상태를 확인하고, 휴대폰 앱에서 실제 기록을 확인해 주세요. 같은 동작을 반복하지 않고 응답을 기다려 주세요.",
        )
        else -> listOf(
            "함께 일해요" to "우리 방에서 근무 시작을 누르세요. 잠깐 쉬기를 누르면 예상 수익과 꾸미기 보상의 시간 계산이 쉬어 가요. 근무 마치기를 누르면 기록을 저장하고 포인트를 정산해요.",
            "예상 수익과 실제 급여" to "기록된 시간과 입력한 시급으로 세전 금액을 단순 계산해요. 세금, 주휴수당, 연장·야간 수당 등은 계산하지 않아요. 실제 지급액과 다를 수 있어요.",
            "일할수록 꾸미기 포인트" to "휴식을 제외한 타이머 근무 10분당 100P를 모아요. 짧은 근무도 같은 날의 시간을 합산해요. 시급과 관계없고 한국 시간 하루 최대 4,800P예요. 한 타이머의 보상은 누적 유급 24시간까지예요.",
            "나만의 방 꾸미기" to "꾸미기에서 아이템을 누르면 방에 적용된 모습을 미리 볼 수 있어요. 구매한 아이템은 보유함에 남고 같은 종류를 한 번에 하나씩 장착해요. 돈을 결제하는 기능은 없어요.",
            "기록을 놓쳤나요?" to "근무 기록에서 +를 눌러 빠진 근무를 추가하세요. 각 구간의 시급을 0원으로 적으면 휴식이에요. 수동 기록이나 편집은 예상 수익에만 반영돼요. 적립한 포인트와 레벨은 기록을 수정·삭제해도 유지돼요.",
            "앱이 닫혀 있어도" to "진행 중인 근무는 저장된 시간으로 이어져요. 재부팅이나 시간이 변경됐을 때는 실제로 확인할 수 있는 시간만 보상해요. 임의로 시계를 바꾸면 포인트가 늘어나지 않아요.",
            "내 기록 보관" to "설정에서 근무와 포인트 내역을 CSV로 내보낼 수 있어요. 자동 계정 동기화와 CSV 복원 기능은 없어요. 앱 삭제나 초기화 전에 필요한 파일을 보관해 주세요.",
        )
    }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.padding(12.dp).widthIn(max = 720.dp).fillMaxWidth().fillMaxHeight(.94f), shape = RoundedCornerShape(28.dp), color = MaterialTheme.colorScheme.background) {
            Column {
                Row(Modifier.fillMaxWidth().padding(start = 22.dp, end = 8.dp, top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                    IconButton(onClick = onDismiss) { Icon(Icons.Rounded.Close, "안내 닫기") }
                }
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(22.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
                    paragraphs.forEach { (heading, text) -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { Text(heading, style = MaterialTheme.typography.titleMedium); Text(text, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
                    if (page == "privacy") OutlinedButton(onClick = openPrivacy) { Icon(Icons.Rounded.OpenInNew, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("공개 개인정보처리방침 열기") }
                }
            }
        }
    }
}
