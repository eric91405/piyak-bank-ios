package com.minseo.piyakbank.platform

import com.minseo.piyakbank.core.*
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.math.BigDecimal
import java.util.UUID

data class UserSettings(
    val wage: Int = 10000,
    val onboarded: Boolean = false,
    val notificationsEnabled: Boolean = false,
    val reminderMinutes: Int = 60,
    val animationEnabled: Boolean = true,
) {
    fun validate() {
        require(wage in 1..1_000_000 && reminderMinutes in listOf(15, 30, 60, 120)) { "설정을 읽지 못했어요." }
    }
}

data class PersistentState(
    val data: AppState,
    val settings: UserSettings = UserSettings(),
    val revision: Long = 0,
    val instanceId: String = UUID.randomUUID().toString(),
    val processedCommands: List<String> = emptyList(),
)

/** Explicit, versioned, strict codec. Unknown/corrupt data never becomes an empty bank. */
object StateCodec {
    private fun obj(vararg pairs: Pair<String, Any?>) = JSONObject().apply {
        pairs.forEach { (key, value) -> put(key, value ?: JSONObject.NULL) }
    }
    private fun <T> array(list: List<T>, encode: (T) -> JSONObject) = JSONArray().apply { list.forEach { put(encode(it)) } }
    private fun <T> JSONArray.read(decode: (JSONObject) -> T) = (0 until length()).map { decode(getJSONObject(it)) }
    private fun JSONObject.long(key: String): Long {
        val value = get(key)
        require(value is Number) { "저장된 숫자 형식을 읽지 못했어요. 원본은 보존됩니다." }
        return try { BigDecimal(value.toString()).longValueExact() }
        catch (_: ArithmeticException) { error("저장된 숫자 범위를 읽지 못했어요. 원본은 보존됩니다.") }
    }
    private fun JSONObject.int(key: String): Int {
        val value = long(key)
        require(value in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) { "저장된 숫자 범위를 읽지 못했어요." }
        return value.toInt()
    }
    private fun JSONObject.string(key: String): String {
        val value = get(key)
        require(value is String) { "저장된 문자 형식을 읽지 못했어요." }
        return value
    }
    private fun JSONObject.boolean(key: String): Boolean {
        val value = get(key)
        require(value is Boolean) { "저장된 설정 형식을 읽지 못했어요." }
        return value
    }
    private fun JSONObject.nullValue(key: String): Boolean {
        require(has(key)) { "저장된 필수 항목이 없어요. 원본은 보존됩니다." }
        return get(key) === JSONObject.NULL
    }
    private fun validateEnvelope(state: PersistentState) {
        fun validId(value: String) = value.length in 1..100 && value.isNotBlank() && value.none { it.isISOControl() }
        require(state.revision >= 0 && validId(state.instanceId)) { "저장소 버전을 읽지 못했어요." }
        require(state.processedCommands.size <= 200 && state.processedCommands.all(::validId) &&
            state.processedCommands.toSet().size == state.processedCommands.size) { "워치 명령 기록을 읽지 못했어요." }
    }
    private fun anchor(a: ClockAnchor) = obj("date" to a.dateMillis, "elapsed" to a.elapsedMillis, "boot" to a.bootId)
    private fun readAnchor(o: JSONObject) = ClockAnchor(o.long("date"), o.long("elapsed"), o.string("boot"))
    private fun segment(s: Segment) = obj("start" to s.startMillis, "end" to s.endMillis, "wage" to s.hourlyWage)
    private fun readSegment(o: JSONObject) = Segment(o.long("start"), if (o.nullValue("end")) null else o.long("end"), o.int("wage"))
    private fun interval(i: Interval) = obj("start" to i.startMillis, "end" to i.endMillis)
    private fun readInterval(o: JSONObject) = Interval(o.long("start"), o.long("end"))
    fun encode(state: PersistentState): String {
        DomainEngine.validate(state.data); state.settings.validate(); validateEnvelope(state)
        val s = state.data
        val core = obj(
            "version" to s.schemaVersion,
            "records" to array(s.records) { obj("id" to it.id, "revision" to it.revision, "segments" to array(it.segments, ::segment)) },
            "active" to s.active?.let { active -> obj(
                "id" to active.id, "segments" to array(active.segments, ::segment),
                "wageAnchor" to anchor(active.wageAnchor),
                "tracking" to active.tracking.let { obj("intervals" to array(it.intervals, ::interval), "anchor" to anchor(it.anchor), "working" to it.working, "captured" to it.capturedMillis) }
            ) },
            "receipts" to array(s.receipts) { obj("id" to it.sessionId, "created" to it.createdMillis, "intervals" to array(it.intervals, ::interval)) },
            "ledger" to array(s.ledger) { obj("id" to it.id, "amount" to it.amount, "kind" to it.kind.name, "created" to it.createdMillis, "related" to it.relatedId) },
            "owned" to array(s.owned) { obj("id" to it.catalogId, "created" to it.acquiredMillis, "equipped" to it.equipped) },
            "clock" to s.rewardClock?.let(::anchor),
        )
        val settings = state.settings.let { obj("wage" to it.wage, "onboarded" to it.onboarded, "notifications" to it.notificationsEnabled, "minutes" to it.reminderMinutes, "animation" to it.animationEnabled) }
        return obj("format" to 1, "revision" to state.revision, "instance" to state.instanceId, "commands" to JSONArray(state.processedCommands), "settings" to settings, "core" to core).toString()
    }
    fun decode(text: String): PersistentState {
        val tokenizer = JSONTokener(text)
        val o = tokenizer.nextValue()
        require(o is JSONObject && tokenizer.nextClean() == '\u0000') { "저장된 문서 형식을 읽지 못했어요." }
        require(o.int("format") == 1) { "더 최신 버전에서 저장한 데이터예요. 앱을 업데이트해 주세요." }
        val s = o.getJSONObject("core")
        val active = if (s.nullValue("active")) null else s.getJSONObject("active").let { a ->
            val t = a.getJSONObject("tracking")
            ActiveSession(a.string("id"), a.getJSONArray("segments").read(::readSegment),
                RewardTracking(t.getJSONArray("intervals").read(::readInterval), readAnchor(t.getJSONObject("anchor")), t.boolean("working"), t.long("captured")), readAnchor(a.getJSONObject("wageAnchor")))
        }
        val data = AppState(
            schemaVersion = s.int("version"),
            records = s.getJSONArray("records").read { WorkRecord(it.string("id"), it.getJSONArray("segments").read(::readSegment), it.long("revision")) },
            active = active,
            receipts = s.getJSONArray("receipts").read { RewardReceipt(it.string("id"), it.getJSONArray("intervals").read(::readInterval), it.long("created")) },
            ledger = s.getJSONArray("ledger").read { PointEntry(it.string("id"), it.long("amount"), PointKind.valueOf(it.string("kind")), it.long("created"), it.string("related")) },
            owned = s.getJSONArray("owned").read { OwnedItem(it.string("id"), it.long("created"), it.boolean("equipped")) },
            rewardClock = if (s.nullValue("clock")) null else readAnchor(s.getJSONObject("clock")),
        )
        val settings = o.getJSONObject("settings").let { UserSettings(it.int("wage"), it.boolean("onboarded"), it.boolean("notifications"), it.int("minutes"), it.boolean("animation")) }
        DomainEngine.validate(data); settings.validate()
        val commands = o.getJSONArray("commands").let { a -> (0 until a.length()).map {
            val value = a.get(it)
            require(value is String) { "워치 명령 형식을 읽지 못했어요." }
            value
        } }
        val revision = o.long("revision"); val instance = o.string("instance")
        return PersistentState(data, settings, revision, instance, commands).also(::validateEnvelope)
    }
}
