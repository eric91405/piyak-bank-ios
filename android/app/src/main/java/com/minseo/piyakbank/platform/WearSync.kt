package com.minseo.piyakbank.platform

import android.content.Context
import com.google.android.gms.wearable.*
import com.minseo.piyakbank.core.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId

object WearSync {
    const val STATE = "/piyak/state"
    const val REQUEST = "/piyak/request"
    const val COMMAND = "/piyak/command"
    const val REPLY = "/piyak/reply"
    fun payload(state: PersistentState, clock: ClockSample, requestId: String? = null): ByteArray {
        val data = DomainEngine.projectActive(state.data, clock)
        val zone = ZoneId.systemDefault()
        val day = Instant.ofEpochMilli(clock.wallMillis).atZone(zone).toLocalDate()
        val total = (data.records.map { it.segments } + listOfNotNull(data.active?.segments)).sumOf { EarningsCalculator.earnedOn(it, day, clock.wallMillis, zone) }
        val body = data.owned.firstOrNull { it.equipped && Catalog.find(it.catalogId)?.slot == DecorSlot.bodyFront }?.catalogId ?: ""
        return JSONObject().apply {
            put("version", 1); put("instance", state.instanceId); put("revision", state.revision)
            put("time", clock.wallMillis); put("onboarded", state.settings.onboarded)
            put("session", data.active?.id ?: ""); put("working", data.active?.tracking?.working == true)
            put("earnings", total); put("points", DomainEngine.balance(data)); put("level", DomainEngine.level(data))
            put("wage", state.settings.wage); put("outfit", body)
            put("stage", WatchCommandPolicy.stageToken(state.instanceId, state.data))
            put("equipped", JSONObject(data.owned.filter { it.equipped }.associate { Catalog.find(it.catalogId)!!.slot.name to it.catalogId }))
            if (requestId != null) put("request", requestId)
        }.toString().toByteArray(Charsets.UTF_8)
    }
    suspend fun publish(context: Context, state: PersistentState, clock: ClockSample) = withTimeout(3_000) {
        val bytes = payload(state, clock)
        val nodes = Wearable.getNodeClient(context).connectedNodes.await()
        for (node in nodes) runCatching { Wearable.getMessageClient(context).sendMessage(node.id, STATE, bytes).await() }
    }
}

/** MessageClient commands are delivered only while connected; no queued offline actions. */
class WearListener : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        val path = event.path
        if (path !in listOf(WearSync.REQUEST, WearSync.COMMAND) || event.data.size > 4096) return
        val source = event.sourceNodeId
        val bytes = event.data.copyOf()
        val repo = (application as PiyakApplication).repository
        repo.scope.launch {
            // The wearable data layer restricts peers to this app's package and signing identity.
            val connected = runCatching { withTimeout(3_000) { Wearable.getNodeClient(this@WearListener).connectedNodes.await().any { it.id == source } } }.getOrDefault(false)
            if (!connected) return@launch
            var id = ""
            try {
                if (path == WearSync.REQUEST) {
                    val requestId = String(bytes, Charsets.UTF_8)
                    require(requestId.length in 1..100)
                    repo.refresh()
                    withTimeout(3_000) { Wearable.getMessageClient(this@WearListener).sendMessage(source, WearSync.STATE, WearSync.payload(repo.snapshot(), repo.clock(), requestId)).await() }
                } else {
                    val command = JSONObject(String(bytes, Charsets.UTF_8)); id = command.getString("id")
                    val state = repo.watchCommand(command)
                    val response = JSONObject().put("id", id).put("ok", true).put("state", JSONObject(String(WearSync.payload(state, repo.clock()), Charsets.UTF_8)))
                    withTimeout(3_000) { Wearable.getMessageClient(this@WearListener).sendMessage(source, WearSync.REPLY, response.toString().toByteArray(Charsets.UTF_8)).await() }
                }
            } catch (e: Exception) {
                val error = JSONObject().put("id", id).put("ok", false).put("error", e.message ?: "휴대폰 연결을 확인하고 다시 시도해 주세요.")
                runCatching { withTimeout(3_000) { Wearable.getMessageClient(this@WearListener).sendMessage(source, WearSync.REPLY, error.toString().toByteArray(Charsets.UTF_8)).await() } }
            }
        }
    }
}
