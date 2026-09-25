package com.minseo.piyakbank.platform

import android.app.Application
import android.net.Uri
import android.os.Bundle
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.OutputStream

internal enum class CsvKind(val value: String, val fileName: String) {
    RECORDS("records", "삐약뱅크_근무기록.csv"),
    POINTS("points", "삐약뱅크_포인트.csv");

    companion object {
        fun from(value: String?) = entries.firstOrNull { it.value == value } ?: RECORDS
    }
}

/** The Activity Result registry restores the picker; its corresponding format must survive too. */
internal class CsvExportRequest {
    var kind: CsvKind = CsvKind.RECORDS
        private set
    fun select(value: String): CsvKind = CsvKind.from(value).also { kind = it }
    fun restore(state: Bundle?) { kind = CsvKind.from(state?.getString(KEY)) }
    fun save(state: Bundle) { state.putString(KEY, kind.value) }
    private companion object { const val KEY = "exportKind" }
}

internal enum class CsvExportResult { SAVED, CANCELLED, FAILED }

/** Only the selected document is written. An export never edits the source database. */
internal class CsvExportCoordinator(
    private val readCsv: suspend (String) -> String,
    private val openOutput: (Uri) -> OutputStream?,
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    suspend fun write(uri: Uri?, kind: CsvKind): CsvExportResult {
        if (uri == null) return CsvExportResult.CANCELLED
        return try {
            withContext(dispatcher) {
                val content = readCsv(kind.value)
                currentCoroutineContext().ensureActive()
                val stream = openOutput(uri) ?: error("파일을 열지 못했어요.")
                stream.use { output ->
                    output.bufferedWriter(Charsets.UTF_8).use { writer ->
                        currentCoroutineContext().ensureActive()
                        writer.write(content)
                    }
                }
                currentCoroutineContext().ensureActive()
            }
            CsvExportResult.SAVED
        } catch (cancelled: CancellationException) {
            // Closing the owning ViewModel cancels work. It must not become a failure toast.
            throw cancelled
        } catch (_: Exception) {
            // A provider can reject the grant, return no stream, or fail during write/close.
            CsvExportResult.FAILED
        }
    }
}

internal data class CsvExportStatus(val writing: Boolean = false, val result: CsvExportResult? = null)

/** Application-only references keep a selected export alive while the Activity is recreated. */
internal class CsvExportViewModel(application: Application) : AndroidViewModel(application) {
    private val exporter = CsvExportCoordinator(
        (application as PiyakApplication).repository::export,
        { application.contentResolver.openOutputStream(it, "wt") },
    )
    private val mutable = MutableStateFlow(CsvExportStatus())
    val status: StateFlow<CsvExportStatus> = mutable

    // Main-thread API, like Activity Result callbacks. An in-flight write cannot be replaced.
    fun start(uri: Uri?, kind: CsvKind, writer: CsvExportCoordinator = exporter): Boolean {
        if (mutable.value.writing) return false
        if (uri == null) return true
        mutable.value = CsvExportStatus(writing = true)
        viewModelScope.launch {
            try { mutable.value = CsvExportStatus(result = writer.write(uri, kind)) }
            catch (cancelled: CancellationException) {
                mutable.value = CsvExportStatus()
                throw cancelled
            }
        }
        return true
    }

    fun consume(result: CsvExportResult) {
        if (mutable.value.result == result) mutable.value = CsvExportStatus()
    }
}
