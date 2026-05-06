package com.example.vertisignage

import android.content.Context

/**
 * Persistent dedupe for announcement IDs across FCM + WebSocket + process restarts.
 */
object PushDedupe {
    private const val PREFS = "vertisignage_push_dedupe"
    private const val KEY_IDS = "announcement_ids"
    private const val MAX_IDS = 64
    private val lock = Any()

    /** Returns true if this announcement should be shown (first consumer); false if duplicate. */
    fun tryConsume(context: Context, announcementId: String): Boolean {
        val appContext = context.applicationContext
        val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        synchronized(lock) {
            val raw = prefs.getString(KEY_IDS, "").orEmpty()
            val q = ArrayDeque(raw.split(',').filter { it.isNotBlank() })
            if (q.contains(announcementId)) return false
            q.addLast(announcementId)
            while (q.size > MAX_IDS) q.removeFirst()
            prefs.edit().putString(KEY_IDS, q.joinToString(",")).apply()
            return true
        }
    }
}
