package com.minseo.piyakbank.platform

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.minseo.piyakbank.core.*
import java.time.Instant
import java.util.UUID
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** Uses isolated synthetic databases only; never opens or deletes the user's bank. */
@RunWith(AndroidJUnit4::class)
class BankDatabaseTest {
    private lateinit var context: Context
    private lateinit var name: String
    private val helpers = mutableListOf<BankDatabase>()
    private val start = ClockSample(Instant.parse("2026-09-20T15:00:00Z").toEpochMilli(), 100_000, "test-boot")
    private val stop = start.copy(wallMillis = start.wallMillis + 600_000, elapsedMillis = start.elapsedMillis + 600_000)
    private fun fresh() = PersistentState(DomainEngine.fresh(start), instanceId = "test-bank")
    private fun open() = BankDatabase(context, name).also { helpers += it }
    private fun rejects(block: () -> Unit) {
        try { block(); fail("Expected operation to fail without replacing the previous snapshot") } catch (_: Exception) { /* expected */ }
    }
    private fun raw(db: BankDatabase): String = db.readableDatabase.rawQuery("SELECT payload FROM bank WHERE id=1", null).use {
        assertTrue(it.moveToFirst()); it.getString(0)
    }

    @Before fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        name = "piyak-test-${UUID.randomUUID()}.db"
    }
    @After fun tearDown() {
        helpers.forEach { it.close() }
        context.deleteDatabase(name)
    }

    @Test fun completedLedgerAndActiveTimerSurviveRealSqliteReopen() {
        val first = open()
        val initial = fresh()
        assertNull(first.read())
        first.save(initial, null)
        val running = initial.copy(data = DomainEngine.start(initial.data, 10_000, start, "work"), revision = 1)
        first.save(running, 0)
        first.close()

        val second = open()
        assertEquals(running, second.read())
        val complete = running.copy(data = DomainEngine.finish(running.data, stop), revision = 2,
            processedCommands = listOf("watch-finish"))
        second.save(complete, 1)
        second.close()

        val persisted = open().read()!!
        assertEquals(complete, persisted)
        assertEquals(100L, DomainEngine.balance(persisted.data))
        assertEquals(1, persisted.data.receipts.size)
    }

    @Test fun independentConnectionCannotOverwriteCommittedStateUsingStaleRevision() {
        val first = open()
        val second = open()
        val initial = fresh()
        first.save(initial, null)
        val stale = second.read()!!
        val new = initial.copy(settings = initial.settings.copy(wage = 25_000), revision = 1)
        first.save(new, 0)
        rejects { second.save(stale.copy(settings = stale.settings.copy(wage = 50_000), revision = 1), 0) }
        assertEquals(new, first.read())
        assertEquals(new, second.read())
    }

    @Test fun databaseEnforcesMonotonicRevisionAndDoesNotAllowSecondInitialization() {
        val db = open()
        val initial = fresh()
        rejects { db.save(initial.copy(revision = 1), null) }
        assertNull(db.read())
        db.save(initial, null)
        rejects { db.save(initial, null) }
        rejects { db.save(initial.copy(settings = initial.settings.copy(wage = 50_000)), 0) }
        rejects { db.save(initial.copy(revision = 2), 0) }
        assertEquals(initial, db.read())
    }

    @Test fun failedSqliteCommitRollsBackWholeSettlementAndRetryCreditsOnce() {
        val db = open()
        val running = fresh().copy(data = DomainEngine.start(fresh().data, 10_000, start, "work"))
        db.save(running, null)
        val completed = running.copy(data = DomainEngine.finish(running.data, stop), revision = 1)
        db.writableDatabase.execSQL("CREATE TRIGGER fail_test_save BEFORE UPDATE ON bank BEGIN SELECT RAISE(ABORT, 'injected save failure'); END")
        rejects { db.save(completed, 0) }
        assertEquals(running, db.read())
        assertEquals(0L, DomainEngine.balance(db.read()!!.data))
        assertTrue(db.read()!!.data.receipts.isEmpty())
        db.writableDatabase.execSQL("DROP TRIGGER fail_test_save")
        db.save(completed, 0)
        assertEquals(completed, db.read())
        assertEquals(100L, DomainEngine.balance(db.read()!!.data))
        assertEquals(1, db.read()!!.data.receipts.size)
    }

    @Test fun corruptPayloadCannotBecomeAnEmptyBankAndOriginalBytesRemainUntouched() {
        val db = open()
        db.save(fresh(), null)
        val damaged = "{\"core\":truncated-original"
        db.writableDatabase.execSQL("UPDATE bank SET payload=? WHERE id=1", arrayOf(damaged))
        rejects { db.read() }
        assertEquals(damaged, raw(db))
        db.close()
        val reopened = open()
        rejects { reopened.read() }
        assertEquals(damaged, raw(reopened))
    }

    @Test fun mismatchingColumnRevisionFailsClosedAndPreservesPayload() {
        val db = open()
        db.save(fresh(), null)
        val original = raw(db)
        db.writableDatabase.execSQL("UPDATE bank SET revision=99 WHERE id=1")
        rejects { db.read() }
        assertEquals(original, raw(db))
    }

    @Test fun invalidStateNeverReachesSqliteAndOriginalSnapshotRemains() {
        val db = open()
        val original = fresh()
        db.save(original, null)
        rejects { db.save(original.copy(data = original.data.copy(owned = emptyList()), revision = 1), 0) }
        assertEquals(original, db.read())
    }

    @Test fun futureSqliteSchemaCannotBeDowngradedOrWiped() {
        val db = open()
        db.save(fresh(), null)
        val original = raw(db)
        db.writableDatabase.execSQL("PRAGMA user_version=2")
        db.close()
        rejects { open().read() }
        SQLiteDatabase.openDatabase(context.getDatabasePath(name).path, null, SQLiteDatabase.OPEN_READONLY).use { preserved ->
            preserved.rawQuery("SELECT payload FROM bank WHERE id=1", null).use {
                assertTrue(it.moveToFirst()); assertEquals(original, it.getString(0))
            }
            assertEquals(2, preserved.version)
        }
    }
}
