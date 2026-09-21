package com.minseo.piyakbank.platform

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/** One atomic snapshot includes wage records, immutable reward receipts, settings and command receipts. */
class BankDatabase(context: Context, name: String = "piyak-bank.db") : SQLiteOpenHelper(context, name, null, 1) {
    override fun onConfigure(db: SQLiteDatabase) { db.setForeignKeyConstraintsEnabled(true) }
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE bank (id INTEGER PRIMARY KEY CHECK(id=1), revision INTEGER NOT NULL, payload TEXT NOT NULL)")
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        error("지원하지 않는 저장소 버전입니다. 원본은 보존됩니다.")
    }
    @Synchronized fun read(): PersistentState? = readableDatabase.rawQuery("SELECT payload, revision FROM bank WHERE id=1", null).use { c ->
        if (!c.moveToFirst()) null else StateCodec.decode(c.getString(0)).also { require(it.revision == c.getLong(1)) }
    }
    @Synchronized fun save(value: PersistentState, expectedRevision: Long?) {
        // Enforce the compare-and-swap contract even if a future caller forgets to
        // increment. Reusing a revision would let a stale writer overwrite new data.
        if (expectedRevision == null) require(value.revision == 0L) { "새 저장소의 버전이 올바르지 않아요." }
        else {
            require(expectedRevision >= 0 && expectedRevision < Long.MAX_VALUE) { "저장소 버전이 올바르지 않아요." }
            require(value.revision == expectedRevision + 1) { "저장소 변경 버전이 올바르지 않아요." }
        }
        val payload = StateCodec.encode(value)
        val db = writableDatabase
        db.beginTransaction()
        try {
            val cv = ContentValues().apply { put("revision", value.revision); put("payload", payload) }
            if (expectedRevision == null) {
                cv.put("id", 1)
                check(db.insertOrThrow("bank", null, cv) != -1L)
            } else {
                check(db.update("bank", cv, "id=1 AND revision=?", arrayOf(expectedRevision.toString())) == 1) { "다른 화면에서 데이터가 변경됐어요. 다시 시도해 주세요." }
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }
}
