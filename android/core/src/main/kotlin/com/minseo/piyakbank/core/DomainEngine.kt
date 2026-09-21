package com.minseo.piyakbank.core

import java.util.UUID

/**
 * Pure state transitions. The caller serializes operations, reloads the latest state, and
 * commits the returned state in one SQLite transaction BEFORE publishing it to observers.
 * If persistence fails, retain the old state. Never persist a partial ledger or receipt.
 */
object DomainEngine {
    fun fresh(now: ClockSample): AppState {
        Bounds.clock(now)
        return AppState(
            owned = Catalog.items.filter { it.defaultOwned }.map { OwnedItem(it.id, now.wallMillis, true) },
            rewardClock = ClockAnchor(now.wallMillis, now.elapsedMillis, now.bootId),
        )
    }

    fun start(state: AppState, wage: Int, now: ClockSample, id: String = UUID.randomUUID().toString()): AppState {
        validate(state); Bounds.clock(now)
        requireDomain(wage in 1..EarningsCalculator.maximumWage, ErrorCode.INVALID_WAGE)
        requireDomain(state.active == null, ErrorCode.ALREADY_WORKING)
        requireDomain(Bounds.id(id) && id.length <= 150 && state.records.none { it.id == id } && state.receipts.none { it.sessionId == id })
        val clock = rewardClock(state.rewardClock, now)
        val session = ActiveSession(id, listOf(Segment(now.wallMillis, null, wage)),
            RewardTracking(emptyList(), clock, true), ClockAnchor(now.wallMillis, now.elapsedMillis, now.bootId))
        return state.copy(active = session, rewardClock = clock)
    }

    /** Safe across process death. Only a known boot and nondecreasing elapsed clock earn time. */
    fun checkpoint(state: AppState, now: ClockSample): AppState {
        validate(state)
        return projectActive(state, now)
    }

    /**
     * Cheap read-only timer projection for a state ALREADY validated at load/commit.
     * Never use this instead of checkpoint/validate before persisting an action.
     * Historical receipts/ledger are immutable and need not be re-unioned every UI tick.
     */
    fun projectActive(state: AppState, now: ClockSample): AppState {
        Bounds.clock(now)
        val active = state.active ?: return state
        validateActive(active, state.rewardClock)
        val clock = rewardClock(state.rewardClock, now)
        val prior = active.tracking
        val measured = elapsed(prior.anchor, now)
        val available = RewardPolicy.maximumSessionMillis - prior.capturedMillis
        val duration = if (prior.working && measured != null) minOf(measured,
            maxOf(0, clock.dateMillis - prior.anchor.dateMillis), available) else 0L
        var intervals = prior.intervals
        if (duration > 0) {
            val interval = Interval(prior.anchor.dateMillis, prior.anchor.dateMillis + duration)
            val last = intervals.lastOrNull()
            intervals = if (last?.endMillis == interval.startMillis) {
                intervals.dropLast(1) + last.copy(endMillis = interval.endMillis)
            } else intervals + interval
        }
        val tracking = prior.copy(intervals = intervals, anchor = clock, capturedMillis = prior.capturedMillis + duration)
        val segments = rebaseWage(active, now)
        return state.copy(active = active.copy(segments = segments, tracking = tracking,
            wageAnchor = ClockAnchor(now.wallMillis, now.elapsedMillis, now.bootId)), rewardClock = clock)
    }

    fun pause(state: AppState, now: ClockSample): AppState {
        val checked = checkpoint(state, now)
        val active = checked.active ?: throw DomainException(ErrorCode.NO_ACTIVE_SESSION)
        if (!active.tracking.working) return checked
        return changeWage(checked, 0, now.wallMillis)
    }

    fun resume(state: AppState, wage: Int, now: ClockSample): AppState {
        requireDomain(wage in 1..EarningsCalculator.maximumWage, ErrorCode.INVALID_WAGE)
        val checked = checkpoint(state, now)
        val active = checked.active ?: throw DomainException(ErrorCode.NO_ACTIVE_SESSION)
        if (active.tracking.working) return checked
        return changeWage(checked, wage, now.wallMillis)
    }

    /** Idempotent once committed: retrying finish on the new state awards nothing. */
    fun finish(state: AppState, now: ClockSample): AppState {
        val checked = checkpoint(state, now)
        val active = checked.active ?: return checked
        requireDomain(checked.receipts.none { it.sessionId == active.id })
        val segments = active.segments.dropLast(1) + active.segments.last().copy(endMillis = now.wallMillis)
        val receipt = RewardReceipt(active.id, active.tracking.intervals, now.wallMillis)
        val previous = RewardPolicy.daily(checked.receipts.flatMap { it.intervals }).associate { it.day to it.points }
        val next = RewardPolicy.daily(checked.receipts.flatMap { it.intervals } + receipt.intervals)
        val entries = next.mapNotNull { day ->
            val delta = day.points - (previous[day.day] ?: 0L)
            if (delta <= 0) null else PointEntry("accrual:${active.id}:${day.day}", delta, PointKind.ACCRUAL,
                day.day.atStartOfDay(RewardPolicy.zone).toInstant().toEpochMilli(), active.id)
        }
        val result = checked.copy(active = null,
            records = checked.records + WorkRecord(active.id, segments),
            receipts = checked.receipts + receipt, ledger = checked.ledger + entries)
        validate(result)
        return result
    }

    fun addRecord(state: AppState, segments: List<Segment>, now: ClockSample,
                  id: String = UUID.randomUUID().toString()): AppState {
        val checked = checkpoint(state, now)
        requireDomain(Bounds.id(id) && checked.records.none { it.id == id } && checked.active?.id != id &&
            checked.receipts.none { it.sessionId == id }, ErrorCode.INVALID_RECORD)
        val sorted = checkedManualSegments(checked, segments, null, now.wallMillis)
        return checked.copy(records = checked.records + WorkRecord(id, sorted))
    }

    fun editRecord(state: AppState, id: String, expectedRevision: Long, segments: List<Segment>, now: ClockSample): AppState {
        val checked = checkpoint(state, now)
        val existing = record(checked, id, expectedRevision)
        requireDomain(existing.revision < Long.MAX_VALUE)
        val sorted = checkedManualSegments(checked, segments, id, now.wallMillis)
        return checked.copy(records = checked.records.map { if (it.id == id) existing.copy(segments = sorted,
            revision = existing.revision + 1) else it })
    }

    fun deleteRecord(state: AppState, id: String, expectedRevision: Long): AppState {
        validate(state)
        record(state, id, expectedRevision)
        // Immutable receipts and the ledger deliberately outlive editable pay records.
        return state.copy(records = state.records.filterNot { it.id == id })
    }

    fun purchase(state: AppState, itemId: String, now: ClockSample, equip: Boolean = true): AppState {
        validate(state); Bounds.clock(now)
        val item = Catalog.find(itemId) ?: throw DomainException(ErrorCode.NOT_FOUND)
        requireDomain(state.owned.none { it.catalogId == itemId }, ErrorCode.ALREADY_OWNED)
        requireDomain(balance(state) >= item.price, ErrorCode.INSUFFICIENT_POINTS)
        val owned = state.owned.map {
            if (equip && Catalog.find(it.catalogId)?.slot == item.slot) it.copy(equipped = false) else it
        } + OwnedItem(itemId, now.wallMillis, equip)
        return state.copy(owned = owned, ledger = state.ledger + PointEntry("purchase:$itemId", -item.price.toLong(),
            PointKind.PURCHASE, now.wallMillis, itemId))
    }

    fun equip(state: AppState, itemId: String): AppState {
        validate(state)
        val item = Catalog.find(itemId) ?: throw DomainException(ErrorCode.NOT_FOUND)
        requireDomain(state.owned.any { it.catalogId == itemId }, ErrorCode.NOT_FOUND)
        return state.copy(owned = state.owned.map {
            if (Catalog.find(it.catalogId)?.slot == item.slot) it.copy(equipped = it.catalogId == itemId) else it
        })
    }

    fun unequip(state: AppState, slot: DecorSlot): AppState {
        validate(state)
        return state.copy(owned = state.owned.map {
            if (Catalog.find(it.catalogId)?.slot == slot) it.copy(equipped = false) else it
        })
    }

    fun balance(state: AppState): Long = state.ledger.fold(0L) { sum, tx -> Math.addExact(sum, tx.amount) }
    fun level(state: AppState): Int = (1 + state.ledger.filter { it.kind == PointKind.ACCRUAL }
        .sumOf { it.amount } / RewardPolicy.pointsPerLevel).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()

    /** Fail closed on damaged or unsupported data. The storage layer must preserve its original bytes. */
    fun validate(state: AppState) {
        requireDomain(state.schemaVersion == 1)
        requireDomain(state.records.map { it.id }.toSet().size == state.records.size)
        state.records.forEach {
            requireDomain(Bounds.id(it.id) && it.revision >= 0)
            validateSegments(it.segments, false)
        }
        // Every v1 bank is initialized with this anchor. Losing it would let a
        // changed wall date reopen the reward calendar, so never silently reseed it.
        requireDomain(state.rewardClock != null)
        state.rewardClock?.let(Bounds::anchor)
        state.active?.let { active ->
            requireDomain(Bounds.id(active.id) && state.records.none { it.id == active.id } && state.rewardClock != null)
            validateActive(active, state.rewardClock)
        }
        requireDomain(state.receipts.map { it.sessionId }.toSet().size == state.receipts.size)
        state.receipts.forEach { receipt ->
            requireDomain(Bounds.id(receipt.sessionId) && receipt.sessionId != state.active?.id && Bounds.date(receipt.createdMillis))
            validateIntervals(receipt.intervals)
            requireDomain(receipt.intervals.sumOf { it.endMillis - it.startMillis } <= RewardPolicy.maximumSessionMillis)
            requireDomain(receipt.intervals.all { it.endMillis <= state.rewardClock!!.dateMillis })
        }
        requireDomain(state.owned.map { it.catalogId }.toSet().size == state.owned.size)
        state.owned.forEach { requireDomain(Catalog.find(it.catalogId) != null && Bounds.date(it.acquiredMillis)) }
        requireDomain(Catalog.items.filter { it.defaultOwned }.all { item -> state.owned.any { it.catalogId == item.id } })
        val equippedSlots = state.owned.filter { it.equipped }.map { Catalog.find(it.catalogId)!!.slot }
        requireDomain(equippedSlots.toSet().size == equippedSlots.size)
        requireDomain(state.ledger.map { it.id }.toSet().size == state.ledger.size)
        val receiptIds = state.receipts.map { it.sessionId }.toSet()
        val ownedIds = state.owned.map { it.catalogId }.toSet()
        state.ledger.forEach { entry ->
            requireDomain(Bounds.id(entry.id) && Bounds.date(entry.createdMillis))
            when (entry.kind) {
                PointKind.ACCRUAL -> requireDomain(entry.amount in 1..RewardPolicy.dailyPointLimit &&
                    entry.relatedId in receiptIds)
                PointKind.PURCHASE -> requireDomain(entry.amount in -1_000_000L..-1L &&
                    entry.relatedId in ownedIds && Catalog.find(entry.relatedId)?.defaultOwned == false)
            }
        }
        val purchases = state.ledger.filter { it.kind == PointKind.PURCHASE }
        requireDomain(purchases.map { it.relatedId }.toSet().size == purchases.size)
        val purchasedIds = purchases.map { it.relatedId }.toSet()
        requireDomain(state.owned.filter { Catalog.find(it.catalogId)?.defaultOwned == false }
            .all { owned -> owned.catalogId in purchasedIds })
        val credited = state.ledger.filter { it.kind == PointKind.ACCRUAL }.sumOf { it.amount }
        requireDomain(credited == RewardPolicy.total(state.receipts.flatMap { it.intervals }))
        requireDomain(balance(state) >= 0)
    }

    private fun rewardClock(prior: ClockAnchor?, now: ClockSample): ClockAnchor {
        val measured = prior?.let { elapsed(it, now) }
        val date = if (measured != null) {
            requireDomain(measured < Bounds.MAX_DATE - prior!!.dateMillis)
            prior.dateMillis + measured
        } else maxOf(prior?.dateMillis ?: now.wallMillis, now.wallMillis)
        requireDomain(Bounds.date(date))
        return ClockAnchor(date, now.elapsedMillis, now.bootId)
    }

    private fun elapsed(anchor: ClockAnchor, now: ClockSample): Long? =
        if (anchor.bootId == now.bootId && now.elapsedMillis >= anchor.elapsedMillis) now.elapsedMillis - anchor.elapsedMillis else null

    private fun rebaseWage(active: ActiveSession, now: ClockSample): List<Segment> {
        val measured = elapsed(active.wageAnchor, now) ?: 0L
        requireDomain(measured < Bounds.MAX_DATE - active.wageAnchor.dateMillis)
        val projected = active.wageAnchor.dateMillis + measured
        val shift = now.wallMillis - projected
        if (shift == 0L) return active.segments
        // A whole-timeline integer translation preserves work/pause fractions exactly.
        return active.segments.map { segment ->
            val start = segment.startMillis + shift
            val end = segment.endMillis?.plus(shift)
            requireDomain(Bounds.date(start) && (end == null || Bounds.date(end)))
            segment.copy(startMillis = start, endMillis = end)
        }
    }

    private fun changeWage(state: AppState, wage: Int, boundary: Long): AppState {
        val active = state.active!!
        val segments = active.segments.dropLast(1) + active.segments.last().copy(endMillis = boundary) +
            Segment(boundary, null, wage)
        return state.copy(active = active.copy(segments = segments, tracking = active.tracking.copy(working = wage > 0)))
    }

    private fun record(state: AppState, id: String, revision: Long): WorkRecord {
        val record = state.records.find { it.id == id } ?: throw DomainException(ErrorCode.NOT_FOUND)
        requireDomain(record.revision == revision, ErrorCode.RECORD_CHANGED)
        return record
    }

    private fun checkedManualSegments(state: AppState, segments: List<Segment>, replacing: String?, now: Long): List<Segment> {
        val sorted = segments.sortedBy { it.startMillis }.toList()
        try { validateSegments(sorted, false) } catch (_: DomainException) { throw DomainException(ErrorCode.INVALID_RECORD) }
        val start = sorted.first().startMillis
        val end = sorted.last().endMillis!!
        requireDomain(sorted.all { it.endMillis!! > it.startMillis && it.endMillis <= now } &&
            end - start <= EarningsCalculator.maximumSessionMillis, ErrorCode.INVALID_RECORD)
        state.records.filterNot { it.id == replacing }.forEach { other ->
            requireDomain(end <= other.segments.first().startMillis || start >= other.segments.last().endMillis!!,
                ErrorCode.INVALID_RECORD)
        }
        state.active?.let { active ->
            requireDomain(end <= active.segments.first().startMillis || start >= now, ErrorCode.INVALID_RECORD)
        }
        return sorted
    }

    private fun validateSegments(segments: List<Segment>, active: Boolean) {
        requireDomain(segments.isNotEmpty())
        segments.forEachIndexed { index, segment ->
            requireDomain(Bounds.date(segment.startMillis) && segment.hourlyWage in 0..EarningsCalculator.maximumWage)
            if (segment.endMillis == null) requireDomain(active && index == segments.lastIndex)
            else requireDomain(Bounds.date(segment.endMillis) && segment.endMillis >= segment.startMillis)
            if (index > 0) requireDomain(segments[index - 1].endMillis!! <= segment.startMillis)
        }
        requireDomain(!active || segments.last().endMillis == null)
    }

    private fun validateActive(active: ActiveSession, rewardClock: ClockAnchor?) {
        requireDomain(Bounds.id(active.id))
        validateSegments(active.segments, true)
        Bounds.anchor(active.wageAnchor); Bounds.anchor(active.tracking.anchor)
        val tracking = active.tracking
        requireDomain(tracking.anchor == rewardClock)
        requireDomain(active.wageAnchor.elapsedMillis == tracking.anchor.elapsedMillis &&
            active.wageAnchor.bootId == tracking.anchor.bootId)
        requireDomain(active.segments.last().startMillis <= active.wageAnchor.dateMillis)
        requireDomain(tracking.working == (active.segments.last().hourlyWage > 0))
        requireDomain(tracking.capturedMillis in 0..RewardPolicy.maximumSessionMillis)
        validateIntervals(tracking.intervals)
        requireDomain(tracking.intervals.sumOf { it.endMillis - it.startMillis } == tracking.capturedMillis)
        requireDomain(tracking.intervals.all { it.endMillis <= tracking.anchor.dateMillis })
    }

    private fun validateIntervals(intervals: List<Interval>) {
        intervals.forEachIndexed { index, interval ->
            requireDomain(RewardPolicy.valid(interval))
            if (index > 0) requireDomain(intervals[index - 1].endMillis <= interval.startMillis)
        }
    }
}
