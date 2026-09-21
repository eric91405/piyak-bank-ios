package com.minseo.piyakbank.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.minseo.piyakbank.platform.PiyakViewModel
import com.minseo.piyakbank.platform.UiState

private enum class AppTab(val title: String, val icon: ImageVector) {
    HOME("우리 방", Icons.Rounded.Home), SHOP("꾸미기", Icons.Rounded.AutoAwesome),
    HISTORY("근무 기록", Icons.Rounded.CalendarMonth), SETTINGS("설정", Icons.Rounded.Settings),
}

@Composable
fun PiyakApp(viewModel: PiyakViewModel, onExport: (String) -> Unit, onRequestNotifications: () -> Unit) {
    val ui by viewModel.ui.collectAsStateWithLifecycle()
    var selected by rememberSaveable { mutableIntStateOf(0) }
    var homeControlsHeight by remember { mutableStateOf(0.dp) }
    val tabState = rememberSaveableStateHolder()
    val snackbar = remember { SnackbarHostState() }
    LaunchedEffect(ui.settings.onboarded) { if (!ui.settings.onboarded) selected = 0 }
    LaunchedEffect(ui.message) {
        ui.message?.let {
            snackbar.showSnackbar(it)
            viewModel.clearMessage()
        }
    }
    PiyakTheme {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            if (ui.data == null) {
                Column(Modifier.fillMaxSize().padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                    if (ui.error == null) {
                        CircularProgressIndicator()
                        Spacer(Modifier.height(20.dp))
                        Text("삐약이의 방을 준비하고 있어요")
                    } else {
                        Icon(Icons.Rounded.CloudOff, null, Modifier.size(52.dp))
                        Spacer(Modifier.height(20.dp))
                        Text("기록을 안전하게 확인하고 있어요", style = MaterialTheme.typography.titleLarge)
                        Spacer(Modifier.height(12.dp))
                        Text(ui.error!!)
                        Spacer(Modifier.height(20.dp))
                        Button(onClick = viewModel::refresh, enabled = !ui.busy) { Text("다시 확인") }
                    }
                }
            } else if (!ui.settings.onboarded) {
                Onboarding(ui, viewModel::onboard)
            } else {
                BackHandler(selected != 0) { selected = 0 }
                BoxWithConstraints(Modifier.fillMaxSize()) {
                    // A short landscape window needs its height for content and timer controls.
                    val wide = maxWidth >= 840.dp || (maxWidth >= 600.dp && maxHeight < 480.dp)
                    Scaffold(
                        containerColor = MaterialTheme.colorScheme.background,
                        // The Home controls sit inside the scaffold content. Lift feedback above
                        // their measured height so a quick pause/finish tap never hits the snackbar.
                        snackbarHost = { SnackbarHost(snackbar, Modifier.padding(bottom = if (selected == 0) homeControlsHeight else 0.dp)) },
                        bottomBar = {
                            if (!wide) NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                                AppTab.entries.forEachIndexed { index, tab ->
                                    NavigationBarItem(selected == index, { selected = index }, { Icon(tab.icon, null) }, label = { Text(tab.title) })
                                }
                            }
                        },
                    ) { insets ->
                        Row(Modifier.fillMaxSize().padding(insets)) {
                            if (wide) NavigationRail(modifier = Modifier.verticalScroll(rememberScrollState()), containerColor = MaterialTheme.colorScheme.background) {
                                Spacer(Modifier.height(28.dp))
                                Icon(Icons.Rounded.EggAlt, "삐약뱅크", Modifier.size(36.dp), tint = MaterialTheme.colorScheme.primary)
                                Spacer(Modifier.height(34.dp))
                                AppTab.entries.forEachIndexed { index, tab ->
                                    NavigationRailItem(selected == index, { selected = index }, { Icon(tab.icon, null) }, label = { Text(tab.title) })
                                    Spacer(Modifier.height(14.dp))
                                }
                            }
                            Box(Modifier.weight(1f).fillMaxHeight()) {
                                tabState.SaveableStateProvider(selected) {
                                    when (selected) {
                                        0 -> HomeScreen(ui, viewModel, onShop = { selected = 1 }, onControlsHeightChanged = { homeControlsHeight = it })
                                        1 -> ShopScreen(ui, viewModel)
                                        2 -> HistoryScreen(ui, viewModel)
                                        else -> SettingsScreen(ui, viewModel, onExport, onRequestNotifications)
                                    }
                                }
                                if (ui.busy) LinearProgressIndicator(Modifier.fillMaxWidth().align(Alignment.TopCenter))
                            }
                        }
                    }
                }
            }
            if (ui.error != null && ui.data != null) {
                DensityAwareAlertDialog(
                    onDismissRequest = viewModel::clearError,
                    title = { Text("다시 확인해 주세요") },
                    text = { Text(ui.error!!) },
                    confirmButton = { TextButton(onClick = viewModel::clearError) { Text("확인") } },
                )
            }
        }
    }
}

@Composable
private fun Onboarding(ui: UiState, onStart: (Int) -> Unit) {
    var wage by rememberSaveable { mutableStateOf(ui.settings.wage.toString()) }
    val valid = wage.toIntOrNull()?.let { it in 1..1_000_000 } == true
    Column(Modifier.fillMaxSize().safeDrawingPadding().imePadding().verticalScroll(rememberScrollState()).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Spacer(Modifier.height(14.dp))
        Text("PIYAK BANK", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
        Text("일하는 시간에\n작은 행복을 더해요", style = MaterialTheme.typography.headlineLarge)
        Room(ui = ui, modifier = Modifier.widthIn(max = 540.dp).fillMaxWidth(), onboarding = true)
        Column(Modifier.widthIn(max = 540.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("함께 일하고, 쉬고, 꾸미는 나만의 삐약이", style = MaterialTheme.typography.titleMedium)
            Text("근무 시간을 기록하면 꾸미기 포인트가 차곡차곡 쌓여요. 계정 없이 이 기기에서 시작해요.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedTextField(
                value = wage, onValueChange = { wage = it.filter(Char::isDigit).take(8) }, label = { Text("기본 시급") },
                suffix = { Text("원") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                isError = !valid, supportingText = { Text("1~1,000,000원 · 나중에 설정에서 바꿀 수 있어요") },
            )
            InfoText("예상 수익은 세전 단순 추정치예요. 시급과 관계없이 타이머 근무 10분에 100P, 하루 최대 4,800P를 받아요.")
            Button(onClick = { wage.toIntOrNull()?.let(onStart) }, enabled = valid && !ui.busy, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp), shape = androidx.compose.foundation.shape.RoundedCornerShape(18.dp)) {
                // Reserve the arrow before measuring a large-font, wrapping label.
                Text(if (ui.busy) "방을 준비하고 있어요" else "삐약이의 방으로", modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                Spacer(Modifier.width(10.dp)); Icon(Icons.Rounded.ArrowForward, null)
            }
            Text("근무 기록은 기기에 저장돼요. 앱을 삭제하면 복구할 수 없으니 설정에서 CSV로 보관해 주세요.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.height(12.dp))
    }
}
