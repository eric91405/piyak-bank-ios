package com.minseo.piyakbank.platform

import android.net.Uri
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.minseo.piyakbank.MainActivity
import com.minseo.piyakbank.core.DomainEngine
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Real ContentResolver writes plus injected failing streams; this does not exercise the SAF picker UI. */
@RunWith(AndroidJUnit4::class)
class ExportCoordinatorTest {
    private lateinit var app: PiyakApplication
    private lateinit var database: BankDatabase
    private lateinit var repository: PiyakRepository
    private lateinit var databaseName: String
    private val documents = mutableListOf<Uri>()

    @Before fun setup() = runBlocking {
        app = ApplicationProvider.getApplicationContext()
        assumeTrue("Document fixtures require the isolated QA app", app.packageName == "com.minseo.piyakbank.uitest")
        databaseName = "export-${UUID.randomUUID()}.db"
        database = BankDatabase(app, databaseName)
        repository = PiyakRepository(app, database) { _, _ -> }
        repository.refresh()
        repository.mutate("CSV fixture") { state, now ->
            val duration = minOf(60_000L, now.elapsedMillis)
            val begin = now.copy(wallMillis = now.wallMillis - duration, elapsedMillis = now.elapsedMillis - duration)
            val data = DomainEngine.finish(DomainEngine.start(DomainEngine.fresh(begin), 12_345, begin), now)
            state.copy(data = data, settings = UserSettings(onboarded = true))
        }
        assertNull(repository.ui.value.error)
    }

    @After fun cleanup() {
        if (::repository.isInitialized) repository.scope.cancel()
        if (::database.isInitialized) database.close()
        if (::databaseName.isInitialized) app.deleteDatabase(databaseName)
        if (::app.isInitialized) documents.forEach { app.contentResolver.delete(it, null, null) }
    }

    private fun document(name: String = "${UUID.randomUUID()}.csv") =
        Uri.parse("content://${app.packageName}.export-test/$name").also { documents += it }
    private fun exporter() = CsvExportCoordinator(repository::export, { app.contentResolver.openOutputStream(it, "wt") })

    @Test fun selectedProviderReceivesExactUtf8BomAndBothActualCsvFormatsWithoutBankChanges() = runBlocking {
        val before = repository.snapshot()
        for (kind in CsvKind.entries) {
            val uri = document()
            val expected = repository.export(kind.value).toByteArray(Charsets.UTF_8)
            assertEquals(CsvExportResult.SAVED, exporter().write(uri, kind))
            val bytes = app.contentResolver.openInputStream(uri)!!.use { it.readBytes() }
            assertArrayEquals(expected, bytes)
            assertArrayEquals(byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()), bytes.take(3).toByteArray())
            assertTrue(bytes.toString(Charsets.UTF_8).contains(if (kind == CsvKind.POINTS) "포인트" else "기록 전체 예상 수익(원)"))
        }
        assertEquals(before, repository.snapshot())
    }

    @Test fun cancelledPickerDoesNotReadOrOpenAnything() = runBlocking {
        val before = repository.snapshot()
        val writer = CsvExportCoordinator({ error("Cancelled picker read the bank") }, { error("Cancelled picker opened a document") })
        assertEquals(CsvExportResult.CANCELLED, writer.write(null, CsvKind.POINTS))
        assertEquals(before, repository.snapshot())
    }

    @Test fun providerWithoutStreamAndRevokedGrantReturnFailureWithoutChangingBank() = runBlocking {
        val before = repository.snapshot()
        assertEquals(CsvExportResult.FAILED, exporter().write(document("null-stream"), CsvKind.RECORDS))
        assertEquals(CsvExportResult.FAILED, exporter().write(document("denied"), CsvKind.POINTS))
        assertEquals(before, repository.snapshot())
    }

    @Test fun writeFailureClosesStreamAndPreservesBank() = runBlocking {
        val before = repository.snapshot()
        var closed = false
        val failing = object : OutputStream() {
            override fun write(value: Int) { throw IOException("Synthetic full provider") }
            override fun close() { closed = true }
        }
        val writer = CsvExportCoordinator(repository::export, { failing })
        assertEquals(CsvExportResult.FAILED, writer.write(document(), CsvKind.RECORDS))
        assertTrue("Failed buffered flush must close the provider stream", closed)
        assertEquals(before, repository.snapshot())
    }

    @Test fun closeFailureIsNotReportedAsSaved() = runBlocking {
        val failing = object : ByteArrayOutputStream() {
            override fun close() { super.close(); throw IOException("Synthetic provider close failure") }
        }
        val writer = CsvExportCoordinator(repository::export, { failing })
        assertEquals(CsvExportResult.FAILED, writer.write(document(), CsvKind.POINTS))
        assertTrue(failing.size() > 0)
    }

    @Test fun lifecycleCancellationDuringReadPropagatesAndNeverOpensDocument() = runBlocking {
        val enteredRead = CompletableDeferred<Unit>()
        val holdRead = CompletableDeferred<Unit>()
        var opened = false
        val writer = CsvExportCoordinator({ enteredRead.complete(Unit); holdRead.await(); "unexpected" }, { opened = true; ByteArrayOutputStream() })
        val task = async { writer.write(document(), CsvKind.POINTS) }
        enteredRead.await()
        task.cancel()
        try { task.await(); fail("Cancellation became an ordinary export result") }
        catch (_: CancellationException) { }
        assertFalse(opened)
    }

    @Test fun providerCancellationPropagatesAndClosesAnOpenedStream() = runBlocking {
        var closed = false
        val stream = object : OutputStream() {
            override fun write(value: Int) { throw CancellationException("Synthetic cancellation during provider write") }
            override fun close() { closed = true }
        }
        try {
            CsvExportCoordinator(repository::export, { stream }).write(document(), CsvKind.POINTS)
            fail("Cancellation became a failure result")
        } catch (_: CancellationException) { }
        assertTrue(closed)
    }

    @Test fun activityRecreationPreservesPendingPointsDocumentFormat() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { assertEquals(CsvKind.POINTS, it.exportRequest.select("points")) }
            scenario.recreate()
            scenario.onActivity { assertEquals(CsvKind.POINTS, it.exportRequest.kind) }
        }
    }

    @Test fun recreationDuringSlowProviderWriteRetainsJobAndWritesSelectedCsvExactlyOnce() = runBlocking {
        val before = repository.snapshot()
        val uri = document()
        val enteredWrite = CountDownLatch(1)
        val finishWrite = CountDownLatch(1)
        val opens = AtomicInteger()
        val writer = CsvExportCoordinator(repository::export, { selectedUri ->
            opens.incrementAndGet()
            val output = app.contentResolver.openOutputStream(selectedUri, "wt")!!
            object : OutputStream() {
                private fun awaitRelease() {
                    enteredWrite.countDown()
                    check(finishWrite.await(30, TimeUnit.SECONDS)) { "Test did not release the slow provider" }
                }
                override fun write(value: Int) { awaitRelease(); output.write(value) }
                override fun write(bytes: ByteArray, offset: Int, length: Int) { awaitRelease(); output.write(bytes, offset, length) }
                override fun flush() = output.flush()
                override fun close() = output.close()
            }
        })
        var retained: CsvExportViewModel? = null
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity { activity ->
                    activity.exportRequest.select("points")
                    retained = activity.csvExports
                    assertTrue(activity.csvExports.start(uri, activity.exportRequest.kind, writer))
                }
                assertTrue("Provider write did not start", enteredWrite.await(10, TimeUnit.SECONDS))
                scenario.recreate()
                scenario.onActivity { activity ->
                    assertSame("The write owner must survive configuration recreation", retained, activity.csvExports)
                    assertEquals(CsvKind.POINTS, activity.exportRequest.kind)
                    assertTrue(activity.csvExports.status.value.writing)
                    assertFalse("A second export must not replace the unfinished one", activity.csvExports.start(uri, CsvKind.RECORDS, writer))
                }
                finishWrite.countDown()
                withTimeout(10_000) { retained!!.status.first { !it.writing } }
                val bytes = app.contentResolver.openInputStream(uri)!!.use { it.readBytes() }
                assertArrayEquals(repository.export("points").toByteArray(Charsets.UTF_8), bytes)
                assertEquals(1, opens.get())
            }
        } finally { finishWrite.countDown() }
        assertEquals(before, repository.snapshot())
    }
}
