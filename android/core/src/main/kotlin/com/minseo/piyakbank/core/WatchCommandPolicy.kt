package com.minseo.piyakbank.core

import java.security.MessageDigest

enum class WatchAction { START, PAUSE, RESUME, FINISH }
data class WatchCommand(
    val id: String,
    val instanceId: String,
    val sessionId: String,
    val stageToken: String,
    val action: WatchAction,
    val createdMillis: Long,
)
data class WatchCommandContext(
    val instanceId: String,
    val onboarded: Boolean,
    val data: AppState,
    val processedIds: List<String>,
)
enum class CommandDecision { APPLY, DUPLICATE }

/** Transport identity is verified by the Android Wear data layer before calling this policy. */
object WatchCommandPolicy {
    /**
     * Checkpoints do not invalidate a visible control. Every timer transition does:
     * an old PAUSE cannot apply after PAUSE→RESUME, or an old START after a finished shift.
     * Receipts survive record deletion and edits. A reset changes the instance identifier.
     */
    fun stageToken(instanceId: String, data: AppState): String {
        require(validId(instanceId)) { "저장소 식별자를 확인해 주세요." }
        val active = data.active
        val text = listOf(instanceId, data.receipts.size.toString(), active?.id ?: "",
            (active?.segments?.size ?: 0).toString()).joinToString("\u001f")
        return MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 255) }
    }

    fun validate(command: WatchCommand, context: WatchCommandContext, nowWallMillis: Long): CommandDecision {
        require(validId(command.id) && validId(command.instanceId)) { "워치 명령 형식이 올바르지 않아요." }
        require(command.instanceId == context.instanceId) { "휴대폰의 최신 상태를 다시 불러와 주세요." }
        require(context.onboarded) { "휴대폰에서 시작 설정을 완료해 주세요." }
        // An ACK lost in transport can be retried after state changes. It never executes twice.
        if (command.id in context.processedIds) return CommandDecision.DUPLICATE
        require(Bounds.date(nowWallMillis) && Bounds.date(command.createdMillis)) { "명령 시간을 확인할 수 없어요." }
        val age = nowWallMillis - command.createdMillis
        require(age in -30_000L..120_000L) { "명령이 만료됐어요. 다시 눌러 주세요." }
        requireCurrentStage(context.instanceId, context.data, command.sessionId, command.stageToken, command.action)
        return CommandDecision.APPLY
    }

    /** Used by local controls too: an old confirmation must not operate on a newer shift. */
    fun requireCurrentStage(instanceId: String, data: AppState, sessionId: String, token: String, action: WatchAction) {
        require(sessionId == (data.active?.id ?: "") && token == stageToken(instanceId, data)) {
            "근무 상태가 달라졌어요. 새로고침해 주세요."
        }
        val active = data.active
        val allowed = when (action) {
            WatchAction.START -> active == null
            WatchAction.PAUSE -> active?.tracking?.working == true
            WatchAction.RESUME -> active != null && !active.tracking.working
            WatchAction.FINISH -> active != null
        }
        require(allowed) { "현재 근무 상태에서 실행할 수 없어요. 새로고침해 주세요." }
    }

    private fun validId(value: String): Boolean = value.length in 1..100 && value.isNotBlank() &&
        value.none { it.isISOControl() }
}
