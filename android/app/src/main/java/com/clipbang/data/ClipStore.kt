package com.clipbang.data

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.util.UUID

/**
 * 一条剪贴记录。字段与移植契约第二节对齐，iOS 侧表结构保持一致。
 */
data class ClipItem(
    val id: String,
    val text: String,
    val createdAt: Long,
    val pinned: Boolean
)

/**
 * 本地存储。用原生 SQLite，不引 Room，避免注解处理器拖慢构建。
 *
 * 规则（写进契约）：
 *   - 最多 99 条，超了删最老的
 *   - 保留 14 天，超期自动清
 *   - 置顶的记录不受上面两条限制
 *   - 相同内容不新增，只把时间刷新并提到最前
 *   - 单条超过 20KB 截断
 */
class ClipStore(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DB_NAME, null, DB_VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE clips (
                id TEXT PRIMARY KEY NOT NULL,
                text TEXT NOT NULL,
                createdAt INTEGER NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX idx_clips_created ON clips(createdAt DESC)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL("DROP TABLE IF EXISTS clips")
        onCreate(db)
    }

    /** 存一条。同内容只刷新时间并提前，不产生重复。 */
    fun put(text: String, now: Long = System.currentTimeMillis()): Boolean {
        if (text.isBlank()) return false

        val stored = if (text.length > MAX_TEXT_LENGTH) text.substring(0, MAX_TEXT_LENGTH) else text
        val db = writableDatabase

        db.beginTransaction()
        try {
            val existingId = findIdByText(db, stored)
            if (existingId != null) {
                val cv = ContentValues().apply { put("createdAt", now) }
                db.update("clips", cv, "id = ?", arrayOf(existingId))
            } else {
                val cv = ContentValues().apply {
                    put("id", UUID.randomUUID().toString())
                    put("text", stored)
                    put("createdAt", now)
                    put("pinned", 0)
                }
                db.insert("clips", null, cv)
                prune(db, now)
            }
            db.setTransactionSuccessful()
            return true
        } finally {
            db.endTransaction()
        }
    }

    /** 按置顶、时间倒序取，最多 99 条 */
    fun list(limit: Int = MAX_COUNT): List<ClipItem> {
        val out = ArrayList<ClipItem>(limit)
        readableDatabase.query(
            TABLE,
            arrayOf("id", "text", "createdAt", "pinned"),
            null,
            null,
            null,
            null,
            "pinned DESC, createdAt DESC",
            limit.toString()
        ).use { cursor ->
            while (cursor.moveToNext()) {
                out.add(
                    ClipItem(
                        id = cursor.getString(0),
                        text = cursor.getString(1),
                        createdAt = cursor.getLong(2),
                        pinned = cursor.getInt(3) == 1
                    )
                )
            }
        }
        return out
    }

    fun setPinned(id: String, pinned: Boolean) {
        val cv = ContentValues().apply { put("pinned", if (pinned) 1 else 0) }
        writableDatabase.update(TABLE, cv, "id = ?", arrayOf(id))
    }

    fun delete(id: String) {
        writableDatabase.delete(TABLE, "id = ?", arrayOf(id))
    }

    /** 启动时清一次，把过期的抹掉 */
    fun purgeExpired(now: Long = System.currentTimeMillis()) {
        writableDatabase.delete(
            TABLE,
            "pinned = 0 AND createdAt < ?",
            arrayOf((now - TTL_MILLIS).toString())
        )
    }

    private fun findIdByText(db: SQLiteDatabase, text: String): String? {
        db.query(TABLE, arrayOf("id"), "text = ?", arrayOf(text), null, null, null, "1").use { c ->
            return if (c.moveToFirst()) c.getString(0) else null
        }
    }

    private fun prune(db: SQLiteDatabase, now: Long) {
        db.delete(
            TABLE,
            "pinned = 0 AND createdAt < ?",
            arrayOf((now - TTL_MILLIS).toString())
        )
        db.execSQL(
            """
            DELETE FROM $TABLE WHERE pinned = 0 AND id NOT IN (
                SELECT id FROM $TABLE ORDER BY pinned DESC, createdAt DESC LIMIT $MAX_COUNT
            )
            """.trimIndent()
        )
    }

    companion object {
        private const val DB_NAME = "clipbang.db"
        private const val DB_VERSION = 1
        private const val TABLE = "clips"

        const val MAX_COUNT = 99
        const val TTL_DAYS = 14
        private const val TTL_MILLIS = TTL_DAYS * 24L * 60 * 60 * 1000
        private const val MAX_TEXT_LENGTH = 20000
    }
}
