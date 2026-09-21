package com.minseo.piyakbank.wear

/** One correlated snapshot request at a time; unrelated pushes cannot replace its nonce. */
internal class SnapshotRequestGate(private val timeoutMillis: Long = 5_000) {
    private data class Pending(val node: String, val id: String, val started: Long)
    private var pending: Pending? = null

    fun canStart(node: String?, nowElapsed: Long): Boolean {
        val previous = pending ?: return true
        return previous.node != node || nowElapsed < previous.started || nowElapsed - previous.started >= timeoutMillis
    }

    fun begin(node: String, id: String, nowElapsed: Long): Boolean {
        require(node.isNotBlank() && id.isNotBlank() && nowElapsed >= 0)
        if (!canStart(node, nowElapsed)) return false
        pending = Pending(node, id, nowElapsed)
        return true
    }

    fun matches(node: String, id: String?): Boolean = id != null && pending?.let { it.node == node && it.id == id } == true

    fun complete(node: String, id: String?): Boolean {
        if (!matches(node, id)) return false
        pending = null
        return true
    }

    fun clear() { pending = null }
}
