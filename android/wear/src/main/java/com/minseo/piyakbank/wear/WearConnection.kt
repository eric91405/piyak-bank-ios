package com.minseo.piyakbank.wear

import android.app.Application
import android.content.Context
import android.os.SystemClock
import com.google.android.gms.wearable.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.tasks.await
import org.json.JSONObject
import java.util.UUID

data class PhoneState(
    val instance: String, val revision: Long, val time: Long, val onboarded: Boolean,
    val session: String, val working: Boolean, val earnings: Long, val points: Long,
    val level: Int, val wage: Int, val outfit: String, val stage: String, val equipped: Map<String, String>,
) {
    companion object {
        fun parse(o: JSONObject): PhoneState {
            require(o.getInt("version") == 1)
            val equipped = o.getJSONObject("equipped").let { value -> value.keys().asSequence().associateWith { value.getString(it) } }
            return PhoneState(o.getString("instance"), o.getLong("revision"), o.getLong("time"), o.getBoolean("onboarded"), o.getString("session"), o.getBoolean("working"), o.getLong("earnings"), o.getLong("points"), o.getInt("level"), o.getInt("wage"), o.getString("outfit"), o.getString("stage"), equipped).also {
                require(it.instance.length in 1..100 && it.revision >= 0 && it.points >= 0 && it.earnings >= 0 && it.level >= 1 && it.wage in 1..1_000_000)
            }
        }
    }
}
data class WearUiState(val phone: PhoneState? = null, val connected: Boolean = false, val busy: Boolean = false, val error: String? = null, val receivedAt: Long = 0)

class WearApplication : Application() {
    val connection: WearConnection by lazy { WearConnection(this) }
}

class WearConnection(private val context: Context) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mutable = MutableStateFlow(WearUiState())
    val ui: StateFlow<WearUiState> = mutable
    private var selectedNode: String? = null
    private var pendingId: String? = null
    private val requests = SnapshotRequestGate()
    private var requesting = false
    private var poll: Job? = null
    private var commandTimeout: Job? = null
    fun visible(visible: Boolean) {
        poll?.cancel()
        if (visible) poll = scope.launch { while (isActive) { request(); delay(15_000) } }
        else mutable.update { it.copy(connected = false) }
    }
    fun refresh() { scope.launch { request() } }
    private suspend fun request() {
        if (requesting || !requests.canStart(selectedNode, SystemClock.elapsedRealtime())) return
        requesting = true
        try {
            withTimeout(5_000) {
                val nodes = Wearable.getCapabilityClient(context).getCapability("piyak_phone_v1", CapabilityClient.FILTER_REACHABLE).await().nodes
                val node = nodes.firstOrNull { it.id == selectedNode } ?: nodes.sortedBy { it.id }.firstOrNull()
                if (node == null) { selectNode(null); mutable.update { it.copy(connected = false) }; return@withTimeout }
                selectNode(node.id)
                val now = SystemClock.elapsedRealtime()
                if (now - mutable.value.receivedAt > 30_000) mutable.update { it.copy(connected = false) }
                val request = UUID.randomUUID().toString()
                if (requests.begin(node.id, request, now)) {
                    Wearable.getMessageClient(context).sendMessage(node.id, "/piyak/request", request.toByteArray(Charsets.UTF_8)).await()
                }
            }
        } catch (_: TimeoutCancellationException) { requests.clear(); mutable.update { it.copy(connected = false) } }
        catch (e: CancellationException) { throw e }
        catch (_: Exception) { requests.clear(); mutable.update { it.copy(connected = false) } }
        finally { requesting = false }
    }
    private fun selectNode(node: String?) {
        if (selectedNode == node) return
        selectedNode = node
        requests.clear()
        pendingId = null
        commandTimeout?.cancel(); commandTimeout = null
        mutable.value = WearUiState()
    }
    fun receive(source: String, path: String, bytes: ByteArray) {
        val copy = bytes.copyOf()
        scope.launch { handleMessage(source, path, copy) }
    }
    private fun handleMessage(source: String, path: String, bytes: ByteArray) {
        if (source != selectedNode || bytes.size > 16_384) return
        try {
            val json = JSONObject(String(bytes, Charsets.UTF_8))
            if (path == "/piyak/state") {
                val request = json.optString("request").takeIf { it.isNotEmpty() }
                val solicited = requests.matches(source, request)
                accept(PhoneState.parse(json), solicited)
                if (solicited) requests.complete(source, request)
            }
            else if (path == "/piyak/reply" && json.getString("id") == pendingId) {
                if (json.getBoolean("ok")) accept(PhoneState.parse(json.getJSONObject("state")))
                else mutable.update { it.copy(error = json.optString("error", "휴대폰에서 상태를 확인해 주세요.")) }
                pendingId = null; commandTimeout?.cancel(); mutable.update { it.copy(busy = false) }
            }
        } catch (_: Exception) { mutable.update { it.copy(error = "상태를 읽지 못했어요. 휴대폰 앱을 업데이트해 주세요.") } }
    }
    private fun accept(phone: PhoneState, solicited: Boolean = false) {
        val previous = mutable.value.phone
        if ((previous == null || previous.instance != phone.instance) && !solicited) {
            // A request triggers an unsolicited phone publish before its correlated
            // reply. Replacing the nonce here would cause a perpetual request loop.
            if (!requesting && requests.canStart(selectedNode, SystemClock.elapsedRealtime())) refresh()
            return
        }
        if (previous != null && previous.instance == phone.instance && phone.revision < previous.revision) return
        mutable.update { it.copy(phone = phone, connected = true, receivedAt = SystemClock.elapsedRealtime()) }
    }
    fun clearError() { mutable.update { it.copy(error = null) } }
    fun command(action: String) {
        val state = mutable.value
        val phone = state.phone ?: return
        val node = selectedNode ?: return
        if (state.busy || !state.connected || SystemClock.elapsedRealtime() - state.receivedAt > 30_000) { refresh(); return }
        val id = UUID.randomUUID().toString()
        pendingId = id
        mutable.update { it.copy(busy = true, error = null) }
        val command = JSONObject().put("id", id).put("action", action).put("instance", phone.instance)
            .put("session", phone.session).put("working", phone.working)
            .put("stage", phone.stage)
            .put("created", phone.time + SystemClock.elapsedRealtime() - state.receivedAt)
        scope.launch {
            try {
                withTimeout(5_000) { Wearable.getMessageClient(context).sendMessage(node, "/piyak/command", command.toString().toByteArray(Charsets.UTF_8)).await() }
                if (pendingId != id || selectedNode != node) return@launch
                commandTimeout = scope.launch {
                    delay(8_000)
                    if (pendingId == id && selectedNode == node) { pendingId = null; mutable.update { it.copy(busy = false, error = "완료 응답이 없어요. 새로고침해 실제 근무 상태를 확인해 주세요.") }; request() }
                }
            } catch (_: Exception) {
                if (pendingId == id && selectedNode == node) { pendingId = null; mutable.update { it.copy(busy = false, connected = false, error = "연결이 끊겼어요. 명령은 오프라인으로 예약하지 않아요.") } }
            }
        }
    }
}

class WatchListener : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        (application as WearApplication).connection.receive(event.sourceNodeId, event.path, event.data)
    }
}
