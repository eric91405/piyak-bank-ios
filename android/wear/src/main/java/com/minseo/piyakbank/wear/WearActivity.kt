package com.minseo.piyakbank.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.minseo.piyakbank.scene.PiyakRoomView
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale

class WearActivity : ComponentActivity() {
    private val connection get() = (application as WearApplication).connection
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { WearHome(connection) }
    }
    override fun onStart() { super.onStart(); connection.visible(true) }
    override fun onStop() { connection.visible(false); super.onStop() }
}

@Composable private fun WearHome(connection: WearConnection) {
    val ui by connection.ui.collectAsStateWithLifecycle()
    val phone = ui.phone
    var confirmFinish by rememberSaveable { mutableStateOf(false) }
    val scrolling = rememberScrollState()
    val scope = rememberCoroutineScope()
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }
    val yellow = Color(0xFFFFDF67)
    MaterialTheme(colorScheme = darkColorScheme(primary = yellow, onPrimary = Color(0xFF302714), background = Color(0xFF131416), surface = Color(0xFF252529))) {
        Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).onRotaryScrollEvent { scope.launch { scrolling.scrollBy(it.verticalScrollPixels) }; true }.focusRequester(focus).focusable().verticalScroll(scrolling).padding(horizontal = 24.dp, vertical = 26.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(9.dp)) {
            Text("삐약뱅크", color = yellow, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            if (phone == null) Image(painterResource(R.drawable.piyak_icon), "삐약이", Modifier.size(64.dp))
            else WatchRoom(phone.equipped)
            Text(if (phone == null) "휴대폰과 함께 시작해요" else "Lv. ${phone.level} · ${phone.points} P", fontSize = 12.sp, color = Color(0xFFDDD6C5), textAlign = TextAlign.Center)
            if (phone != null) {
                Text("${NumberFormat.getIntegerInstance(Locale.KOREA).format(phone.earnings)}원", fontSize = 27.sp, fontWeight = FontWeight.Bold, color = Color.White)
                Text("휴대폰 동기화 기준 예상 수익", color = Color(0xFFCBC6BC), fontSize = 11.sp, textAlign = TextAlign.Center)
            }
            val status = when { !ui.connected -> "휴대폰 연결 대기"; phone?.onboarded != true -> "휴대폰에서 시작 설정을 완료해 주세요"; phone.session.isEmpty() -> "함께 일할 준비가 됐어요"; phone.working -> "삐약이와 근무 중"; else -> "잠시 쉬고 있어요" }
            Text(status, fontSize = 12.sp, color = Color.White, textAlign = TextAlign.Center)
            ui.error?.let { Text(it, color = Color(0xFFFFB9B9), fontSize = 12.sp, textAlign = TextAlign.Center) }
            if (ui.busy) { CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp); Text("휴대폰 저장 확인 중", fontSize = 11.sp, color = Color.White) }
            val enabled = ui.connected && phone?.onboarded == true && !ui.busy
            if (confirmFinish) {
                Text("근무를 마치고 정산할까요?", color = Color.White, textAlign = TextAlign.Center, fontSize = 13.sp)
                Button(onClick = { connection.command("finish"); confirmFinish = false }, enabled = enabled, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("마치기") }
                OutlinedButton(onClick = { confirmFinish = false }, modifier = Modifier.fillMaxWidth()) { Text("취소") }
            } else {
                val action = when { phone?.session.isNullOrEmpty() -> "start"; phone?.working == true -> "pause"; else -> "resume" }
                val label = when (action) { "start" -> "근무 시작"; "pause" -> "잠깐 쉬기"; else -> "다시 일하기" }
                Button(onClick = { connection.command(action) }, enabled = enabled, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp), shape = RoundedCornerShape(24.dp)) { Text(label) }
                if (!phone?.session.isNullOrEmpty()) OutlinedButton(onClick = { confirmFinish = true }, enabled = enabled, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("근무 마치기") }
            }
            TextButton(onClick = { connection.clearError(); connection.refresh() }, modifier = Modifier.heightIn(min = 48.dp)) { Text("새로고침") }
            Text("연결 중에만 제어할 수 있어요.\n포인트는 휴대폰에서 정산돼요.", color = Color(0xFFBBB7AE), fontSize = 10.sp, textAlign = TextAlign.Center)
            Spacer(Modifier.height(12.dp))
        }
    }
}

@Composable private fun WatchRoom(equipped: Map<String, String>) {
    var room by remember { mutableStateOf<PiyakRoomView?>(null) }
    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner, room) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) room?.onHostResume()
            if (event == Lifecycle.Event.ON_PAUSE) room?.onHostPause()
        }
        owner.lifecycle.addObserver(observer)
        if (owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) room?.onHostResume()
        onDispose { owner.lifecycle.removeObserver(observer); room?.onHostPause() }
    }
    AndroidView(factory = { PiyakRoomView(it).also { view -> room = view } },
        update = { it.configure(equipped, animated = false, working = false); it.contentDescription = "휴대폰에서 꾸민 삐약이의 방" },
        modifier = Modifier.fillMaxWidth().height(110.dp))
}
