package com.minseo.piyakbank.platform

import com.minseo.piyakbank.core.*
import java.time.Instant
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class StateCodecTest {
    private val start = ClockSample(Instant.parse("2026-09-20T15:00:00Z").toEpochMilli(), 100_000, "boot-test")
    private val end = start.copy(wallMillis = start.wallMillis + 28_800_000, elapsedMillis = start.elapsedMillis + 28_800_000)
    private fun fresh() = PersistentState(DomainEngine.fresh(start), instanceId = "bank-instance")
    private fun rejects(block: () -> Unit) {
        try { block(); fail("Corrupt or unsupported state must fail closed") } catch (_: Exception) { /* expected */ }
    }
    private fun changed(change: (JSONObject) -> Unit): String = JSONObject(StateCodec.encode(fresh())).also(change).toString()

    @Test fun completeBankRoundTripsWithoutLosingLedgerReceiptsEquipmentOrRevisions() {
        var data = DomainEngine.start(fresh().data, 10_000, start, "work")
        data = DomainEngine.finish(data, end)
        data = DomainEngine.purchase(data, "bodyFront.stripe_tee", end)
        data = DomainEngine.editRecord(data, "work", 0, data.records.single().segments.map { it.copy(hourlyWage = 12_000) }, end)
        val original = PersistentState(data, UserSettings(20_000, true, true, 30, false), 17,
            "bank-instance", listOf("watch-start-1", "watch-finish-2"))
        assertEquals(original, StateCodec.decode(StateCodec.encode(original)))
    }

    @Test fun activePausedTimerAndItsIndependentClockAnchorsRoundTrip() {
        val active = DomainEngine.start(fresh().data, 10_000, start, "work")
        val paused = DomainEngine.pause(active, end.copy(wallMillis = end.wallMillis - 3_600_000))
        val original = fresh().copy(data = paused, revision = 1)
        val reopened = StateCodec.decode(StateCodec.encode(original))
        assertEquals(original, reopened)
        val reopenedActive = reopened.data.active!!
        assertFalse(reopenedActive.tracking.working)
        assertEquals(4800L, RewardPolicy.total(reopenedActive.tracking.intervals))
    }

    @Test fun explicitNullsRoundTripButMissingNullableKeysAreNotTreatedAsEmptyData() {
        val encoded = StateCodec.encode(fresh())
        assertEquals(fresh(), StateCodec.decode(encoded))
        rejects { StateCodec.decode(changed { it.getJSONObject("core").remove("active") }) }
        rejects { StateCodec.decode(changed { it.getJSONObject("core").remove("clock") }) }
        val active = fresh().copy(data = DomainEngine.start(fresh().data, 10_000, start, "work"))
        val missingEnd = JSONObject(StateCodec.encode(active)).apply {
            getJSONObject("core").getJSONObject("active").getJSONArray("segments").getJSONObject(0).remove("end")
        }
        rejects { StateCodec.decode(missingEnd.toString()) }
    }

    @Test fun futureEnvelopeAndCoreVersionsAreRejectedWithoutFreshFallback() {
        rejects { StateCodec.decode(changed { it.put("format", 2) }) }
        rejects { StateCodec.decode(changed { it.getJSONObject("core").put("version", 2) }) }
    }

    @Test fun numericStringsFractionsAndOverflowCannotCoerceIntoValidValues() {
        rejects { StateCodec.decode(changed { it.put("revision", "0") }) }
        rejects { StateCodec.decode(changed { it.put("revision", 0.5) }) }
        rejects { StateCodec.decode(changed { it.getJSONObject("settings").put("wage", 4_294_977_296L) }) }
        rejects { StateCodec.decode(changed { it.getJSONObject("core").getJSONObject("clock").put("elapsed", "100000") }) }
        rejects { StateCodec.decode(changed { it.getJSONObject("settings").put("minutes", 30.9) }) }
    }

    @Test fun settingsBooleansAndIdentifiersMustHaveCorrectJsonTypes() {
        rejects { StateCodec.decode(changed { it.getJSONObject("settings").put("onboarded", "true") }) }
        rejects { StateCodec.decode(changed { it.put("instance", 42) }) }
        rejects { StateCodec.decode(changed { it.put("commands", JSONArray().put(42)) }) }
    }

    @Test fun missingTruncatedAndTrailingDataAreRejected() {
        rejects { StateCodec.decode("{\"core\":") }
        rejects { StateCodec.decode(StateCodec.encode(fresh()) + " trailing") }
        rejects { StateCodec.decode("[]") }
        rejects { StateCodec.decode(changed { it.remove("settings") }) }
        rejects { StateCodec.decode(changed { it.getJSONObject("core").remove("receipts") }) }
    }

    @Test fun invalidSettingsCannotEnterOrLeavePersistentStorage() {
        rejects { StateCodec.encode(fresh().copy(settings = UserSettings(wage = 0))) }
        rejects { StateCodec.encode(fresh().copy(settings = UserSettings(reminderMinutes = 1))) }
        rejects { StateCodec.decode(changed { it.getJSONObject("settings").put("wage", 1_000_001) }) }
    }

    @Test fun encodeAndDecodeApplySameEnvelopeValidation() {
        rejects { StateCodec.encode(fresh().copy(revision = -1)) }
        rejects { StateCodec.encode(fresh().copy(instanceId = " ")) }
        rejects { StateCodec.encode(fresh().copy(processedCommands = listOf("duplicate", "duplicate"))) }
        rejects { StateCodec.decode(changed { it.put("revision", -1) }) }
        rejects { StateCodec.decode(changed { it.put("commands", JSONArray(listOf("duplicate", "duplicate"))) }) }
        val boundary = fresh().copy(processedCommands = (0 until 200).map { "command-$it" })
        assertEquals(boundary, StateCodec.decode(StateCodec.encode(boundary)))
        rejects { StateCodec.encode(boundary.copy(processedCommands = boundary.processedCommands + "one-too-many")) }
    }

    @Test fun coreCorruptionIsRejectedEvenWhenJsonIsWellFormed() {
        rejects { StateCodec.decode(changed { it.getJSONObject("core").put("clock", JSONObject.NULL) }) }
        rejects { StateCodec.decode(changed { it.getJSONObject("core").put("owned", JSONArray()) }) }
        rejects { StateCodec.decode(changed { it.getJSONObject("core").put("ledger", JSONArray().put(JSONObject()
            .put("id", "fabricated").put("amount", 100).put("kind", "ACCRUAL").put("created", start.wallMillis).put("related", "missing"))) }) }
        val earned = DomainEngine.finish(DomainEngine.start(fresh().data, 10_000, start, "work"), end)
        val corrupted = JSONObject(StateCodec.encode(fresh().copy(data = earned))).apply {
            getJSONObject("core").getJSONArray("receipts").getJSONObject(0).put("intervals", JSONArray())
        }
        rejects { StateCodec.decode(corrupted.toString()) }
    }

    @Test fun immutableReceiptsRemainAfterEditedRecordIsDeletedAndReloaded() {
        val completed = DomainEngine.finish(DomainEngine.start(fresh().data, 10_000, start, "work"), end)
        val deleted = DomainEngine.deleteRecord(completed, "work", 0)
        val reopened = StateCodec.decode(StateCodec.encode(fresh().copy(data = deleted)))
        assertTrue(reopened.data.records.isEmpty())
        assertEquals(1, reopened.data.receipts.size)
        assertEquals(4800L, DomainEngine.balance(reopened.data))
    }
}
