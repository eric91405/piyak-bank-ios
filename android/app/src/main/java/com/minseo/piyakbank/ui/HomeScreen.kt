package com.minseo.piyakbank.ui

import android.view.View
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.minseo.piyakbank.core.*
import com.minseo.piyakbank.platform.PiyakViewModel
import com.minseo.piyakbank.platform.UiState
import com.minseo.piyakbank.scene.PiyakRoomView
import java.time.Instant
import java.time.ZoneId

@Composable
internal fun HomeScreen(ui: UiState, viewModel: PiyakViewModel, onShop: () -> Unit, onControlsHeightChanged: (Dp) -> Unit = {}) {
    val data = ui.data ?: return
    val density = LocalDensity.current
    var confirm by rememberSaveable { mutableStateOf<String?>(null) }
    var confirmSession by rememberSaveable { mutableStateOf("") }
    var confirmStage by rememberSaveable { mutableStateOf("") }
    var submittedAt by rememberSaveable { mutableStateOf<Long?>(null) }
    val active = data.active
    val running = active?.segments?.lastOrNull()?.hourlyWage?.let { it > 0 } == true
    ActionCompletion(ui, submittedAt) { confirm = null; submittedAt = null }
    val zone = ZoneId.systemDefault()
    val today = Instant.ofEpochMilli(ui.now).atZone(zone).toLocalDate()
    val completedToday = remember(data.records, today, zone) {
        data.records.sumOf { EarningsCalculator.earnedOn(it.segments, today, ui.now, zone) }
    }
    val activeToday = active?.let { EarningsCalculator.earnedOn(it.segments, today, ui.now, zone) } ?: 0L
    val todayPay = completedToday + activeToday
    Column(Modifier.fillMaxSize()) {
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val wide = maxWidth >= 760.dp
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Column(Modifier.widthIn(max = 1080.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    ScreenHeading("삐약이의 하루", today.format(KoreanDate)) { PointBadge(DomainEngine.balance(data)) }
                    if (wide) {
                        Row(horizontalArrangement = Arrangement.spacedBy(22.dp), verticalAlignment = Alignment.Top) {
                            Column(Modifier.weight(1.15f), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                                Room(ui, animationChanged = { viewModel.updateAnimation(it) })
                                GrowthCard(data)
                            }
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                                EarningsCard(ui, todayPay, running)
                                ShopLink(onShop)
                            }
                        }
                    } else {
                        Room(ui, animationChanged = { viewModel.updateAnimation(it) })
                        EarningsCard(ui, todayPay, running)
                        GrowthCard(data)
                        ShopLink(onShop)
                    }
                }
            }
        }
        Surface(modifier = Modifier.onSizeChanged { size -> onControlsHeightChanged(with(density) { size.height.toDp() }) }, shadowElevation = 4.dp, color = MaterialTheme.colorScheme.surface) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                if (active == null) {
                    Button(onClick = { confirmSession = ""; confirmStage = ui.timerStage; confirm = "start" }, enabled = !ui.busy, modifier = Modifier.widthIn(max = 640.dp).fillMaxWidth().heightIn(min = 56.dp), shape = RoundedCornerShape(18.dp)) {
                        Icon(Icons.Rounded.PlayArrow, null); Spacer(Modifier.width(8.dp)); Text("삐약이와 근무 시작", modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                    }
                } else {
                    Row(Modifier.widthIn(max = 740.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        FilledTonalButton(onClick = { if (running) viewModel.pause(active.id, ui.timerStage) else viewModel.resume(active.id, ui.timerStage) }, enabled = !ui.busy, modifier = Modifier.weight(1f).heightIn(min = 56.dp), shape = RoundedCornerShape(18.dp)) {
                            Icon(if (running) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, null)
                            Spacer(Modifier.width(5.dp)); Text(if (running) "잠깐 쉬기" else "다시 근무")
                        }
                        Button(onClick = { confirmSession = active.id; confirmStage = ui.timerStage; confirm = "finish" }, enabled = !ui.busy, modifier = Modifier.weight(1f).heightIn(min = 56.dp), shape = RoundedCornerShape(18.dp)) {
                            Icon(Icons.Rounded.Check, null); Spacer(Modifier.width(5.dp)); Text("근무 마치기")
                        }
                    }
                }
            }
        }
    }
    if (confirm != null) DensityAwareAlertDialog(
        onDismissRequest = { if (!ui.busy) { confirm = null; submittedAt = null } },
        icon = { Icon(if (confirm == "start") Icons.Rounded.WbSunny else Icons.Rounded.Celebration, null) },
        title = { Text(if (confirm == "start") "오늘도 함께 일해요" else "근무를 마치고 기록할까요?") },
        text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (confirm == "start") {
                Text("기본 시급 ${ui.settings.wage.toLong().won()}으로 예상 수익을 기록해요.")
                Text("시급은 설정에서 바꿀 수 있어요. 근무 중에는 잠깐 쉬기를 눌러 휴식을 기록해 주세요.")
            } else Text("근무 기록을 저장하고 꾸미기 포인트를 받아요. 휴식을 제외한 타이머 근무 시간으로 계산해요.")
            InfoText("10분에 100P · 한국 시간 하루 최대 4,800P\n같은 날의 짧은 근무 시간도 합산해요.")
            if (confirmStage != ui.timerStage) ErrorText("다른 화면에서 근무 상태가 변경됐어요. 닫은 뒤 다시 확인해 주세요.")
            ErrorText(ui.error)
        } },
        confirmButton = { Button(onClick = { submittedAt = ui.actionRevision; if (confirm == "start") viewModel.start(confirmStage) else viewModel.finish(confirmSession, confirmStage) }, enabled = !ui.busy && confirmStage == ui.timerStage) { Text(if (confirm == "start") "근무 시작" else "근무 마치기") } },
        dismissButton = { TextButton(onClick = { confirm = null; submittedAt = null }, enabled = !ui.busy) { Text("취소") } },
    )
}

@Composable
internal fun Room(
    ui: UiState,
    modifier: Modifier = Modifier,
    onboarding: Boolean = false,
    previewItemId: String? = null,
    animationChanged: ((Boolean) -> Unit)? = null,
) {
    val lifecycleOwner = LocalLifecycleOwner.current
    var room by remember { mutableStateOf<PiyakRoomView?>(null) }
    var activity by remember { mutableStateOf("반가워! 오늘도 함께해") }
    var controls by rememberSaveable { mutableStateOf(false) }
    val data = ui.data
    val equipped = remember(data?.owned) {
        data?.owned.orEmpty().filter { it.equipped }.mapNotNull { owned -> Catalog.items.find { it.id == owned.catalogId }?.let { it.slot.name to it.id } }.toMap()
    }
    val working = data?.active?.tracking?.working == true
    DisposableEffect(lifecycleOwner, room) {
        val current = room
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> current?.onHostResume()
                Lifecycle.Event.ON_PAUSE -> current?.onHostPause()
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        if (lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) current?.onHostResume()
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer); current?.onHostPause() }
    }
    Column(modifier.clip(RoundedCornerShape(30.dp)).background(Brush.linearGradient(listOf(Lavender, Peach))), verticalArrangement = Arrangement.spacedBy(0.dp)) {
        Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 18.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Rounded.AutoAwesome, null, Modifier.size(18.dp), tint = WarmInk)
            Text(if (previewItemId != null) "우리 방에 놓아 볼까요?" else activity, color = WarmInk, style = MaterialTheme.typography.labelLarge, modifier = Modifier.weight(1f))
            if (!onboarding && data != null) Text("Lv. ${DomainEngine.level(data)}", color = WarmInk, style = MaterialTheme.typography.labelLarge)
        }
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val roomHeight = (maxWidth * 0.77f).coerceIn(230.dp, 380.dp)
            // Keep the spoken description on a Compose parent. AndroidView's native
            // accessibility exclusion otherwise also hides semantics on its modifier.
            Box(Modifier.fillMaxWidth().height(roomHeight).semantics(mergeDescendants = true) {
                contentDescription = "삐약이와 가구가 있는 3D 방. 아래 버튼으로 놀아 주거나 시점을 바꿀 수 있어요."
            }) {
                AndroidView(
                    factory = { context -> PiyakRoomView(context).also { view ->
                        view.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
                        view.onInteraction = { activity = "함께 놀아 줘서 고마워!" }
                        view.onActivityChanged = { activity = it }
                        room = view
                    } },
                    update = { it.configure(equipped, ui.settings.animationEnabled && previewItemId == null, working, previewItemId) },
                    modifier = Modifier.matchParentSize(),
                )
            }
        }
        if (!onboarding) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                IconButton(onClick = { controls = !controls }) { Icon(Icons.Rounded.RotateRight, "방 시점 조절", tint = WarmInk) }
                if (animationChanged != null) IconButton(onClick = { animationChanged(!ui.settings.animationEnabled) }, enabled = !ui.busy) {
                    Icon(if (ui.settings.animationEnabled) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, if (ui.settings.animationEnabled) "삐약이 움직임 멈추기" else "삐약이 움직임 재생", tint = WarmInk)
                }
                FilledTonalButton(onClick = { room?.playInteraction() }, colors = ButtonDefaults.filledTonalButtonColors(containerColor = androidx.compose.ui.graphics.Color.White, contentColor = WarmInk)) {
                    Icon(Icons.Rounded.TouchApp, null, Modifier.size(19.dp)); Spacer(Modifier.width(5.dp)); Text("놀아주기")
                }
            }
            if (controls) FlowRow(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
                IconButton(onClick = { room?.rotateBy(-15f) }) { Icon(Icons.Rounded.RotateLeft, "왼쪽으로 회전", tint = WarmInk) }
                IconButton(onClick = { room?.rotateBy(15f) }) { Icon(Icons.Rounded.RotateRight, "오른쪽으로 회전", tint = WarmInk) }
                IconButton(onClick = { room?.zoomBy(1.15f) }) { Icon(Icons.Rounded.ZoomIn, "방 확대", tint = WarmInk) }
                IconButton(onClick = { room?.zoomBy(0.87f) }) { Icon(Icons.Rounded.ZoomOut, "방 축소", tint = WarmInk) }
                IconButton(onClick = { room?.resetCamera() }) { Icon(Icons.Rounded.CenterFocusStrong, "기본 시점으로", tint = WarmInk) }
            }
        }
        Text(if (previewItemId != null) "미리보기는 구매하거나 장착하기 전까지 저장되지 않아요" else "삐약이를 톡 누르거나 방을 돌려 보세요", color = WarmInk.copy(alpha = .75f), style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(horizontal = 18.dp, vertical = 12.dp))
    }
}

@Composable
private fun EarningsCard(ui: UiState, amount: Long, working: Boolean) {
    val data = ui.data ?: return
    val active = data.active
    val rewardZone = ZoneId.of("Asia/Seoul")
    val today = Instant.ofEpochMilli(ui.now).atZone(rewardZone).toLocalDate()
    val points = remember(data.receipts, today) { RewardPolicy.daily(data.receipts.flatMap { it.intervals }).find { it.day == today }?.points ?: 0L }
    GameCard {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("오늘의 예상 수익", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            if (active != null) Text(if (working) "● 근무 중" else "Ⅱ 쉬는 중", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelLarge)
        }
        Text(amount.won(), style = MaterialTheme.typography.displaySmall)
        if (active != null) {
            Text("유급 ${paidTime(active.segments, ui.now)}", style = MaterialTheme.typography.bodyMedium)
            Text("이번 근무 ${EarningsCalculator.total(active.segments, ui.now).won()}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (EarningsCalculator.workingMillis(active.segments, ui.now) > 12 * 3_600_000L) InfoText("근무를 마쳤나요? 한 타이머의 보상은 누적 유급 24시간까지만 계산돼요. 예상 수익은 계속 기록돼요.")
        }
        Text("세전 단순 추정치 · 실제 급여와 다를 수 있어요", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        Text("오늘 근무로 받은 꾸미기 포인트", style = MaterialTheme.typography.bodySmall)
        Text("${points.points()} / 4,800 P", style = MaterialTheme.typography.titleMedium)
        InfoText("시급과 무관하게 타이머 10분에 100P\n근무를 마치면 적립돼요. 한도는 근무한 날의 한국 시간 00시 기준이에요.")
    }
}

@Composable
private fun GrowthCard(data: AppState) {
    val earned = data.ledger.filter { it.kind == PointKind.ACCRUAL }.sumOf { it.amount }
    val level = DomainEngine.level(data)
    GameCard(color = MaterialTheme.colorScheme.secondaryContainer) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(Icons.Rounded.EmojiEvents, null, Modifier.size(32.dp), tint = MaterialTheme.colorScheme.onSecondaryContainer)
            Column {
                Text("함께 자라는 삐약이", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSecondaryContainer)
                Text("Lv. $level · 함께 모은 ${earned.points()}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSecondaryContainer)
            }
        }
        LinearProgressIndicator(progress = { (earned % 4800).toFloat() / 4800f }, modifier = Modifier.fillMaxWidth().height(7.dp).clip(RoundedCornerShape(50)), color = MaterialTheme.colorScheme.secondary)
        Text("다음 레벨까지 ${(4800 - earned % 4800).points()} · 아이템을 사도 레벨은 유지돼요", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSecondaryContainer)
    }
}

@Composable
private fun ShopLink(onClick: () -> Unit) {
    FilledTonalButton(onClick, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(24.dp), colors = ButtonDefaults.filledTonalButtonColors(containerColor = MaterialTheme.colorScheme.tertiaryContainer, contentColor = MaterialTheme.colorScheme.onTertiaryContainer), contentPadding = PaddingValues(20.dp)) {
        Icon(Icons.Rounded.Redeem, null, Modifier.size(32.dp))
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("작은 방, 커다란 취향", style = MaterialTheme.typography.titleMedium)
            Text("모은 포인트로 우리 방을 꾸며요", style = MaterialTheme.typography.bodySmall)
        }
        Icon(Icons.Rounded.ChevronRight, null)
    }
}
