package com.minseo.piyakbank.platform

import android.app.Application
import android.os.SystemClock
import android.provider.Settings
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.minseo.piyakbank.core.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

data class UiState(
    val data: AppState? = null,
    val settings: UserSettings = UserSettings(),
    val now: Long = System.currentTimeMillis(),
    val busy: Boolean = false,
    val error: String? = null,
    val message: String? = null,
    val actionRevision: Long = 0,
)

class PiyakApplication : Application() {
    val repository: PiyakRepository by lazy { PiyakRepository(this) }
    override fun onCreate() { super.onCreate(); repository.initialize() }
}

class PiyakRepository(private val app: Application) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()
    private val systemMutex = Mutex()
    private val db = BankDatabase(app)
    private var current: PersistentState? = null
    private val unknownBoot = "unverified-${UUID.randomUUID()}"
    private val mutable = MutableStateFlow(UiState())
    val ui: StateFlow<UiState> = mutable
    fun clock(): ClockSample {
        val boot = runCatching { Settings.Global.getInt(app.contentResolver, Settings.Global.BOOT_COUNT, -1) }.getOrDefault(-1)
        return ClockSample(System.currentTimeMillis(), SystemClock.elapsedRealtime(), if (boot >= 0) "boot:$boot" else unknownBoot)
    }
    fun initialize() { scope.launch { refresh() } }
    suspend fun refresh() = withContext(Dispatchers.IO) {
        val refreshed = mutex.withLock {
            try {
                var state = db.read()
                if (state == null) {
                    state = PersistentState(DomainEngine.fresh(clock()))
                    db.save(state, null)
                }
                val checked = DomainEngine.checkpoint(state.data, clock())
                if (checked != state.data) {
                    val next = state.copy(data = checked, revision = Math.addExact(state.revision, 1))
                    db.save(next, state.revision); state = next
                }
                current = state
                publish(state)
                true
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { showError(e); false }
        }
        if (refreshed) synchronizeSystem()
    }
    private fun publish(state: PersistentState) {
        mutable.update { it.copy(data = state.data, settings = state.settings, now = clock().wallMillis) }
    }
    fun tick() {
        scope.launch {
            mutex.withLock {
                val state = current ?: return@withLock
                val sample = clock()
                try { mutable.update { it.copy(data = DomainEngine.projectActive(state.data, sample), now = sample.wallMillis) } }
                catch (e: Exception) { showError(e) }
            }
        }
    }
    suspend fun mutate(message: String, action: (PersistentState, ClockSample) -> PersistentState) = withContext(Dispatchers.IO) {
        val committed = mutex.withLock {
            try {
                mutable.update { it.copy(busy = true, error = null, message = null) }
                val prior = db.read() ?: error("저장소를 먼저 열어 주세요.")
                val next = action(prior, clock()).copy(revision = Math.addExact(prior.revision, 1))
                db.save(next, prior.revision)
                current = next
                publish(next)
                mutable.update { it.copy(busy = false, message = message, actionRevision = it.actionRevision + 1) }
                true
            } catch (e: CancellationException) {
                mutable.update { it.copy(busy = false) }
                throw e
            } catch (e: Exception) { showError(e); false }
        }
        if (committed) synchronizeSystem()
    }
    private fun showError(e: Exception) {
        val message = when (e) {
            is DomainException -> e.code.messageKorean
            is IllegalArgumentException, is IllegalStateException -> e.message ?: "저장된 기록을 확인하지 못했어요. 원본은 보존됩니다."
            else -> "저장하거나 읽지 못했어요. 기존 기록은 보존됩니다. 저장 공간을 확인하고 다시 시도해 주세요."
        }
        mutable.update { it.copy(busy = false, error = message) }
    }
    fun clearError() { mutable.update { it.copy(error = null) } }
    fun clearMessage() { mutable.update { it.copy(message = null) } }
    suspend fun snapshot(): PersistentState = withContext(Dispatchers.IO) { mutex.withLock { db.read() ?: error("데이터 준비 중이에요.") } }
    private suspend fun synchronizeSystem() = systemMutex.withLock {
        val state = mutex.withLock { current } ?: return@withLock
        // Side effects never turn a successful database commit into a failed money operation.
        runCatching { ReminderScheduler.synchronize(app, state) }
        runCatching { PiyakWidget.updateAll(app, state, clock()) }
        runCatching { WearSync.publish(app, state, clock()) }
        currentCoroutineContext().ensureActive()
    }
    /** An alarm cannot publish an older working snapshot after a pause/disable commit. */
    suspend fun deliverReminder() = withContext(Dispatchers.IO) {
        systemMutex.withLock {
            mutex.withLock stateLock@ {
                val state = db.read() ?: return@stateLock
                ReminderScheduler.synchronize(app, state, delivered = true)
            }
        }
    }
    suspend fun watchCommand(command: JSONObject): PersistentState = withContext(Dispatchers.IO) {
        val result = mutex.withLock {
            val prior = db.read() ?: error("휴대폰에서 앱을 먼저 열어 주세요.")
            val now = clock()
            fun text(key: String) = (command.get(key) as? String) ?: error("명령 형식이 올바르지 않아요.")
            val created = command.get("created")
            require(created is Long || created is Int)
            val parsed = WatchCommand(text("id"), text("instance"), text("session"), text("stage"), WatchAction.valueOf(text("action").uppercase(java.util.Locale.ROOT)), (created as Number).toLong())
            val context = WatchCommandContext(prior.instanceId, prior.settings.onboarded, prior.data, prior.processedCommands)
            if (WatchCommandPolicy.validate(parsed, context, now.wallMillis) == CommandDecision.DUPLICATE) return@withLock prior
            val data = when (parsed.action) {
                WatchAction.START -> DomainEngine.start(prior.data, prior.settings.wage, now)
                WatchAction.PAUSE -> DomainEngine.pause(prior.data, now)
                WatchAction.RESUME -> DomainEngine.resume(prior.data, prior.settings.wage, now)
                WatchAction.FINISH -> DomainEngine.finish(prior.data, now)
            }
            val next = prior.copy(data = data, revision = Math.addExact(prior.revision, 1), processedCommands = (prior.processedCommands + parsed.id).takeLast(200))
            db.save(next, prior.revision)
            current = next; publish(next)
            next
        }
        synchronizeSystem()
        result
    }
    suspend fun export(kind: String): String {
        val s = snapshot()
        fun cell(v: Any?): String {
            var text = v?.toString() ?: ""
            if (text.trimStart().firstOrNull() in listOf('=', '+', '-', '@')) text = "'$text"
            return "\"${text.replace("\"", "\"\"")}\""
        }
        fun row(vararg values: Any?) = values.joinToString(",", transform = ::cell)
        val zone = ZoneId.systemDefault()
        fun date(value: Long) = Instant.ofEpochMilli(value).atZone(zone).toOffsetDateTime().toString()
        val lines = if (kind == "points") {
            listOf(row("ID", "일시", "종류", "포인트", "관련 ID")) + s.data.ledger.map { row(it.id, date(it.createdMillis), it.kind.name, it.amount, it.relatedId) }
        } else {
            listOf(row("기록 ID", "시작", "종료", "시급", "기록 전체 예상 수익(원)", "상태")) +
                s.data.records.flatMap { record -> record.segments.mapIndexed { i, segment -> row(record.id, date(segment.startMillis), segment.endMillis?.let(::date), segment.hourlyWage, if (i == 0) EarningsCalculator.total(record.segments, clock().wallMillis) else "", "완료") } }
        }
        return "\uFEFF" + lines.joinToString("\r\n") + "\r\n"
    }
}

class PiyakViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = (application as PiyakApplication).repository
    val ui = repository.ui
    private var ticker: Job? = null
    fun visible(value: Boolean) {
        ticker?.cancel()
        if (value) ticker = viewModelScope.launch {
            repository.refresh()
            var seconds = 0
            while (isActive) { delay(1_000); repository.tick(); if (++seconds % 15 == 0) repository.refresh() }
        } else repository.scope.launch { repository.refresh() }
    }
    private fun act(message: String, block: (PersistentState, ClockSample) -> PersistentState) { viewModelScope.launch { repository.mutate(message, block) } }
    fun onboard(wage: Int) = act("삐약이의 방에 오신 걸 환영해요!") { s, _ -> s.copy(settings = s.settings.copy(wage = wage, onboarded = true).also { it.validate() }) }
    fun start() = act("근무를 시작했어요.") { s, t -> check(s.settings.onboarded); s.copy(data = DomainEngine.start(s.data, s.settings.wage, t)) }
    fun pause() = act("잠시 쉬어요.") { s, t -> s.copy(data = DomainEngine.pause(s.data, t)) }
    fun resume() = act("다시 함께 일해요.") { s, t -> s.copy(data = DomainEngine.resume(s.data, s.settings.wage, t)) }
    fun finish() = act("근무를 마치고 포인트를 정산했어요.") { s, t -> s.copy(data = DomainEngine.finish(s.data, t)) }
    fun purchase(id: String) = act("새 아이템을 구매하고 꾸몄어요.") { s, t -> s.copy(data = DomainEngine.purchase(s.data, id, t)) }
    fun equip(id: String) = act("꾸미기를 적용했어요.") { s, _ -> s.copy(data = DomainEngine.equip(s.data, id)) }
    fun unequip(slot: DecorSlot) = act("보관함에 넣었어요.") { s, _ -> s.copy(data = DomainEngine.unequip(s.data, slot)) }
    fun updateSettings(settings: UserSettings) = act("설정을 저장했어요.") { s, _ -> settings.validate(); s.copy(settings = settings) }
    fun addRecord(segments: List<Segment>) = act("기록을 추가했어요. 꾸미기 포인트는 변하지 않아요.") { s, t -> s.copy(data = DomainEngine.addRecord(s.data, segments, t)) }
    fun editRecord(id: String, revision: Long, segments: List<Segment>) = act("기록을 수정했어요. 꾸미기 포인트는 유지돼요.") { s, t -> s.copy(data = DomainEngine.editRecord(s.data, id, revision, segments, t)) }
    fun deleteRecord(id: String, revision: Long) = act("기록을 삭제했어요. 꾸미기 포인트는 유지돼요.") { s, _ -> s.copy(data = DomainEngine.deleteRecord(s.data, id, revision)) }
    fun reset() = act("모든 기록을 초기화했어요.") { s, t -> PersistentState(DomainEngine.fresh(t), revision = s.revision) }
    fun clearMessage() = repository.clearMessage()
    fun clearError() = repository.clearError()
    fun refresh() { viewModelScope.launch { repository.refresh() } }
}
