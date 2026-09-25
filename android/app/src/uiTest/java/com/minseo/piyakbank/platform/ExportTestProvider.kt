package com.minseo.piyakbank.platform

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File

/** Actual ContentResolver boundary for isolated instrumentation; absent from release/debug. */
class ExportTestProvider : ContentProvider() {
    override fun onCreate() = true
    private fun file(uri: Uri): File {
        val name = requireNotNull(uri.lastPathSegment)
        require(name.matches(Regex("[A-Za-z0-9_.-]{1,100}")))
        return File(requireNotNull(context).cacheDir, "csv-provider-$name")
    }
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        if (uri.lastPathSegment == "null-stream") return null
        if (uri.lastPathSegment == "denied") throw SecurityException("Synthetic revoked document grant")
        return ParcelFileDescriptor.open(file(uri), ParcelFileDescriptor.parseMode(mode))
    }
    override fun getType(uri: Uri) = "text/csv"
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor =
        MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)).apply { addRow(arrayOf(file(uri).name, file(uri).length())) }
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = if (file(uri).delete()) 1 else 0
    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
}
