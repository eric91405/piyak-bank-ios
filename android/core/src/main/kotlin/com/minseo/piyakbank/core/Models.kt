package com.minseo.piyakbank.core

/** All times are integer milliseconds. No Android, disk, network, or UI dependencies. */
data class ClockSample(val wallMillis: Long, val elapsedMillis: Long, val bootId: String)
data class ClockAnchor(val dateMillis: Long, val elapsedMillis: Long, val bootId: String)
data class Segment(val startMillis: Long, val endMillis: Long?, val hourlyWage: Int)
data class WorkRecord(val id: String, val segments: List<Segment>, val revision: Long = 0)
data class Interval(val startMillis: Long, val endMillis: Long)
data class RewardTracking(
    val intervals: List<Interval>,
    val anchor: ClockAnchor,
    val working: Boolean,
    val capturedMillis: Long = 0,
)
data class ActiveSession(
    val id: String,
    val segments: List<Segment>,
    val tracking: RewardTracking,
    val wageAnchor: ClockAnchor,
)
enum class PointKind { ACCRUAL, PURCHASE }
data class PointEntry(
    val id: String,
    val amount: Long,
    val kind: PointKind,
    val createdMillis: Long,
    val relatedId: String,
)
data class OwnedItem(val catalogId: String, val acquiredMillis: Long, val equipped: Boolean)
data class RewardReceipt(val sessionId: String, val intervals: List<Interval>, val createdMillis: Long)
data class AppState(
    val schemaVersion: Int = 1,
    val records: List<WorkRecord> = emptyList(),
    val active: ActiveSession? = null,
    val receipts: List<RewardReceipt> = emptyList(),
    val ledger: List<PointEntry> = emptyList(),
    val owned: List<OwnedItem> = emptyList(),
    val rewardClock: ClockAnchor? = null,
)

@Suppress("EnumEntryName")
enum class DecorSlot(val isRoom: Boolean, val label: String) {
    bg(true, "배경"), wallDeco(true, "벽 장식"), bigFurniture(true, "가구"),
    floorProp(true, "소품"), rug(true, "러그"), headTop(false, "모자"),
    eyes(false, "안경"), headband(false, "머리 장식"), neck(false, "목 장식"),
    bodyFront(false, "의상"),
}
data class CatalogItem(
    val id: String,
    val slot: DecorSlot,
    val name: String,
    val price: Int,
    val defaultOwned: Boolean,
)

enum class ErrorCode(val messageKorean: String) {
    INVALID_WAGE("시급은 1원부터 1,000,000원까지 입력해 주세요."),
    INVALID_RECORD("시간과 시급을 확인해 주세요. 기록은 미래이거나 겹칠 수 없어요."),
    CORRUPT_STATE("저장된 기록을 읽지 못했어요. 원본은 보존되니 지원팀에 문의해 주세요."),
    ALREADY_WORKING("이미 진행 중인 근무가 있어요."),
    NO_ACTIVE_SESSION("진행 중인 근무가 없어요."),
    NOT_FOUND("항목을 찾을 수 없어요. 화면을 닫고 다시 열어 주세요."),
    RECORD_CHANGED("다른 화면에서 기록이 변경됐어요. 다시 열어 최신 기록을 확인해 주세요."),
    ALREADY_OWNED("이미 보유한 아이템이에요."),
    INSUFFICIENT_POINTS("포인트가 부족해요. 근무를 마치면 포인트를 받을 수 있어요."),
}
class DomainException(val code: ErrorCode) : IllegalStateException(code.messageKorean)

internal fun requireDomain(value: Boolean, code: ErrorCode = ErrorCode.CORRUPT_STATE) {
    if (!value) throw DomainException(code)
}

internal object Bounds {
    // Keep java.time calendar arithmetic, subtraction and exports in a civil-date range.
    const val MIN_DATE = -62_135_596_800_000L // 0001-01-01 UTC
    const val MAX_DATE = 253_402_214_400_000L // 9999-12-31 UTC, exclusive
    fun date(value: Long): Boolean = value in MIN_DATE until MAX_DATE
    fun id(value: String): Boolean = value.isNotBlank() && value.length <= 200 && value.none { it.isISOControl() }
    fun clock(value: ClockSample) {
        requireDomain(date(value.wallMillis) && value.elapsedMillis >= 0 && id(value.bootId))
    }
    fun anchor(value: ClockAnchor) {
        requireDomain(date(value.dateMillis) && value.elapsedMillis >= 0 && id(value.bootId))
    }
}
