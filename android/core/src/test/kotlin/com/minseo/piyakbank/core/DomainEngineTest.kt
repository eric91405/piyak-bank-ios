package com.minseo.piyakbank.core

import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class DomainEngineTest {
    private val initial = ClockSample(Instant.parse("2026-09-20T15:00:00Z").toEpochMilli(), 100_000, "boot-1")
    private fun after(millis: Long, wall: Long = millis, boot: String = initial.bootId) =
        ClockSample(initial.wallMillis + wall, initial.elapsedMillis + millis, boot)
    private fun fresh() = DomainEngine.fresh(initial)
    private fun working(wage: Int = 10_000) = DomainEngine.start(fresh(), wage, initial, "work-1")
    private fun failure(code: ErrorCode, action: () -> Unit) {
        try { action(); fail("Expected $code") } catch (error: DomainException) { assertEquals(code, error.code) }
    }

    @Test fun catalogMatchesAll81SharedIdsAndFourDefaults() {
        assertEquals(81, Catalog.items.size)
        assertEquals(81, Catalog.items.map { it.id }.toSet().size)
        assertEquals(4, Catalog.items.count { it.defaultOwned })
        assertTrue(Catalog.items.all { it.id.startsWith(it.slot.name + ".") })
        DomainEngine.validate(fresh())
        assertEquals(0L, DomainEngine.balance(fresh()))
    }

    @Test fun wagesNeverChangeRewardCurrency() {
        for (wage in listOf(1, 10_000, 1_000_000)) {
            val state = DomainEngine.finish(working(wage), after(600_000))
            assertEquals(100L, DomainEngine.balance(state))
            assertEquals(wage.toLong() / 6, EarningsCalculator.total(state.records.single().segments, after(600_000).wallMillis))
        }
    }

    @Test fun finishingTwiceDoesNotDuplicateReceiptsOrPoints() {
        val complete = DomainEngine.finish(working(), after(600_000))
        assertEquals(complete, DomainEngine.finish(complete, after(1_200_000)))
        assertEquals(1, complete.receipts.size)
        assertEquals(1, complete.ledger.size)
    }

    @Test fun duplicateStartAndInvalidWageLeaveOriginalUntouched() {
        val state = working()
        failure(ErrorCode.ALREADY_WORKING) { DomainEngine.start(state, 10_000, initial) }
        failure(ErrorCode.INVALID_WAGE) { DomainEngine.start(fresh(), 0, initial) }
        failure(ErrorCode.INVALID_WAGE) { DomainEngine.start(fresh(), 1_000_001, initial) }
        assertEquals(0L, DomainEngine.balance(state))
        assertEquals(1, state.active!!.segments.size)
    }

    @Test fun pausesExcludePayAndPointsWhileWageChangesApplyOnlyAfterResume() {
        val paused = DomainEngine.pause(working(), after(600_000))
        assertFalse(paused.active!!.tracking.working)
        val resumed = DomainEngine.resume(paused, 20_000, after(1_200_000))
        val complete = DomainEngine.finish(resumed, after(1_800_000))
        assertEquals(listOf(10_000, 0, 20_000), complete.records.single().segments.map { it.hourlyWage })
        assertEquals(5_000L, EarningsCalculator.total(complete.records.single().segments, after(1_800_000).wallMillis))
        assertEquals(200L, DomainEngine.balance(complete))
    }

    @Test fun checkpointRecoveryMatchesUninterruptedTimer() {
        val base = working()
        val checkpointed = DomainEngine.checkpoint(base, after(300_000))
        val recovered = DomainEngine.finish(checkpointed.copy(), after(600_000))
        val uninterrupted = DomainEngine.finish(base, after(600_000))
        assertEquals(uninterrupted, recovered)
        assertEquals(0, base.active!!.tracking.intervals.size) // pure transition never mutated source
    }

    @Test fun saveFailureCanKeepOriginalAndRetryWithoutLosingTimeOrDoubleAward() {
        val original = working()
        val uncommitted = DomainEngine.finish(original, after(600_000))
        assertEquals(100L, DomainEngine.balance(uncommitted))
        // Simulate repository commit throwing: the old state remains the only published state.
        val retry = DomainEngine.finish(original, after(600_000))
        assertEquals(uncommitted, retry)
        assertEquals(0L, DomainEngine.balance(original))
        assertTrue(original.receipts.isEmpty())
    }

    @Test fun forwardAndBackwardClockChangesPreserveMeasuredPayAndPointCalendar() {
        for (wall in listOf(-3_000_000L, 60_000_000L)) {
            val result = DomainEngine.finish(working(), after(600_000, wall))
            assertEquals(100L, DomainEngine.balance(result))
            assertEquals(1666L, EarningsCalculator.total(result.records.single().segments, after(600_000, wall).wallMillis))
            assertEquals(initial.wallMillis, result.receipts.single().intervals.single().startMillis)
            assertEquals(initial.wallMillis + 600_000, result.receipts.single().intervals.single().endMillis)
        }
    }

    @Test fun repeatedDateChangesBetweenSessionsCannotReopenSameBootDailyCap() {
        val earned = DomainEngine.finish(working(), after(28_800_000))
        assertEquals(4800L, DomainEngine.balance(earned))
        val changed = after(28_800_000, 10 * 86_400_000L)
        val second = DomainEngine.start(earned, 1_000_000, changed, "work-2")
        val complete = DomainEngine.finish(second, after(29_400_000, 10 * 86_400_000L + 600_000))
        assertEquals(4800L, DomainEngine.balance(complete))
    }

    @Test fun rebootDiscardsUnmeasuredGapButPreservesCheckpointedAndNewTime() {
        val checkpoint = DomainEngine.checkpoint(working(), after(600_000))
        val reboot = ClockSample(initial.wallMillis + 86_400_000, 900_000, "boot-2")
        val recovered = DomainEngine.checkpoint(checkpoint, reboot)
        assertEquals(1666L, EarningsCalculator.total(recovered.active!!.segments, reboot.wallMillis))
        val stopped = DomainEngine.finish(recovered, reboot.copy(wallMillis = reboot.wallMillis + 600_000,
            elapsedMillis = reboot.elapsedMillis + 600_000))
        assertEquals(200L, DomainEngine.balance(stopped))
        assertEquals(3333L, EarningsCalculator.total(stopped.records.single().segments, reboot.wallMillis + 600_000))
    }

    @Test fun backwardsClockAfterRebootRetainsCheckpointedPay() {
        val checkpoint = DomainEngine.checkpoint(working(), after(600_000))
        val reboot = ClockSample(initial.wallMillis - 3_600_000, 900_000, "boot-2")
        val recovered = DomainEngine.checkpoint(checkpoint, reboot)
        assertEquals(1666L, EarningsCalculator.total(recovered.active!!.segments, reboot.wallMillis))
        assertEquals(600_000L, recovered.active.tracking.capturedMillis)
    }

    @Test fun decreasingElapsedClockIsTreatedAsUnknownBootTime() {
        val checkpoint = DomainEngine.checkpoint(working(), after(600_000))
        val reset = after(800_000).copy(elapsedMillis = 10)
        val completed = DomainEngine.finish(checkpoint, reset)
        assertEquals(100L, DomainEngine.balance(completed))
        assertEquals(1666L, EarningsCalculator.total(completed.records.single().segments, reset.wallMillis))
    }

    @Test fun oneSessionCanCaptureAtMostTwentyFourHoursEvenAcrossSeveralDays() {
        val complete = DomainEngine.finish(working(), after(3 * 86_400_000L))
        assertEquals(86_400_000L, complete.receipts.single().intervals.sumOf { it.endMillis - it.startMillis })
        assertEquals(4800L, DomainEngine.balance(complete)) // starts exactly at KST midnight
        assertEquals(720_000L, EarningsCalculator.total(complete.records.single().segments, after(3 * 86_400_000L).wallMillis))
    }

    @Test fun zeroPointReceiptsPreserveFractionsAcrossSessions() {
        var state = DomainEngine.finish(working(), after(3000))
        assertEquals(0L, DomainEngine.balance(state))
        state = DomainEngine.start(state, 10_000, after(3000), "work-2")
        state = DomainEngine.finish(state, after(6000))
        assertEquals(1L, DomainEngine.balance(state))
        assertEquals(2, state.receipts.size)
    }

    @Test fun editingAndDeletingPayCannotCreateOrReclaimPoints() {
        val completed = DomainEngine.finish(working(), after(600_000))
        val updated = DomainEngine.editRecord(completed, "work-1", 0,
            listOf(Segment(initial.wallMillis, initial.wallMillis + 600_000, 1_000_000)), after(600_000))
        val deleted = DomainEngine.deleteRecord(updated, "work-1", 1)
        assertEquals(100L, DomainEngine.balance(deleted))
        assertEquals(completed.receipts, deleted.receipts)
        assertTrue(deleted.records.isEmpty())
    }

    @Test fun staleEditorOrDeleteConfirmationCannotOverwriteAnotherWindow() {
        val completed = DomainEngine.finish(working(), after(600_000))
        val segments = completed.records.single().segments.map { it.copy(hourlyWage = 20_000) }
        val updated = DomainEngine.editRecord(completed, "work-1", 0, segments, after(600_000))
        failure(ErrorCode.RECORD_CHANGED) { DomainEngine.editRecord(updated, "work-1", 0, segments, after(600_000)) }
        failure(ErrorCode.RECORD_CHANGED) { DomainEngine.deleteRecord(updated, "work-1", 0) }
        val deleted = DomainEngine.deleteRecord(updated, "work-1", 1)
        failure(ErrorCode.NOT_FOUND) { DomainEngine.editRecord(deleted, "work-1", 1, segments, after(600_000)) }
    }

    @Test fun manualRecordsHaveNoReceiptsAndCannotOverlapOrUseFutureDates() {
        val manual = DomainEngine.addRecord(fresh(), listOf(Segment(initial.wallMillis - 3_600_000, initial.wallMillis, 1_000_000)), initial, "manual")
        assertEquals(0L, DomainEngine.balance(manual))
        assertTrue(manual.receipts.isEmpty())
        failure(ErrorCode.INVALID_RECORD) { DomainEngine.addRecord(manual,
            listOf(Segment(initial.wallMillis - 1000, initial.wallMillis, 10_000)), initial) }
        failure(ErrorCode.INVALID_RECORD) { DomainEngine.addRecord(fresh(),
            listOf(Segment(initial.wallMillis, initial.wallMillis + 1000, 10_000)), initial) }
        failure(ErrorCode.INVALID_RECORD) { DomainEngine.addRecord(fresh(),
            listOf(Segment(initial.wallMillis - 8 * 86_400_000L, initial.wallMillis, 10_000)), initial) }
    }

    @Test fun purchaseDeductsOnceEquipsSingleSlotAndNeverChangesGrowth() {
        val earned = DomainEngine.finish(working(), after(28_800_000))
        val bought = DomainEngine.purchase(earned, "bodyFront.stripe_tee", after(28_800_000))
        assertEquals(4050L, DomainEngine.balance(bought))
        assertEquals(2, DomainEngine.level(bought))
        assertFalse(bought.owned.single { it.catalogId == "bodyFront.hoodie_mint" }.equipped)
        assertTrue(bought.owned.single { it.catalogId == "bodyFront.stripe_tee" }.equipped)
        failure(ErrorCode.ALREADY_OWNED) { DomainEngine.purchase(bought, "bodyFront.stripe_tee", after(28_800_000)) }
        val unequipped = DomainEngine.unequip(bought, DecorSlot.bodyFront)
        val reequipped = DomainEngine.equip(unequipped, "bodyFront.hoodie_mint")
        assertEquals(1, reequipped.owned.count { it.equipped && Catalog.find(it.catalogId)!!.slot == DecorSlot.bodyFront })
        assertEquals(4050L, DomainEngine.balance(reequipped))
        DomainEngine.validate(reequipped)
    }

    @Test fun insufficientFundsCannotPartiallyGrantOwnershipOrChangeLedger() {
        val state = fresh()
        failure(ErrorCode.INSUFFICIENT_POINTS) { DomainEngine.purchase(state, "headTop.crown", initial) }
        assertEquals(4, state.owned.size)
        assertTrue(state.ledger.isEmpty())
    }

    @Test fun invalidStateFailsClosedInsteadOfRegeneratingMoneyOrResettingData() {
        failure(ErrorCode.CORRUPT_STATE) { DomainEngine.validate(fresh().copy(schemaVersion = 999)) }
        failure(ErrorCode.CORRUPT_STATE) { DomainEngine.validate(fresh().copy(rewardClock = null)) }
        failure(ErrorCode.CORRUPT_STATE) { DomainEngine.validate(fresh().copy(owned = emptyList())) }
        failure(ErrorCode.CORRUPT_STATE) { DomainEngine.validate(fresh().copy(ledger = listOf(
            PointEntry("fake", 100, PointKind.ACCRUAL, initial.wallMillis, "missing")))) }
        val working = working()
        failure(ErrorCode.CORRUPT_STATE) { DomainEngine.validate(working.copy(active = working.active!!.copy(
            tracking = working.active.tracking.copy(capturedMillis = 600_000)))) }
    }

    @Test fun immediatePauseResumeAndFinishStillProduceValidZeroDurationRecord() {
        val paused = DomainEngine.pause(working(), initial)
        val resumed = DomainEngine.resume(paused, 10_000, initial)
        val complete = DomainEngine.finish(resumed, initial)
        assertEquals(0L, DomainEngine.balance(complete))
        DomainEngine.validate(complete)
    }

    @Test fun displayProjectionMatchesDurableCheckpointAcrossClockChangesAndBoots() {
        val working = working()
        val paused = DomainEngine.pause(working, after(6000))
        for (state in listOf(working, paused)) {
            for (clock in listOf(after(60_000), after(60_000, -3_600_000), after(60_000, 86_400_000),
                after(60_000, 86_400_000, "other-boot"))) {
                assertEquals(DomainEngine.checkpoint(state, clock), DomainEngine.projectActive(state, clock))
            }
        }
        assertEquals(fresh(), DomainEngine.projectActive(fresh(), initial))
    }
}
