package com.example.vertisignage

import android.content.Context
import android.os.Build

/**
 * Persists the in-flight recovery attempt id for correlating native → UI visibility timing.
 */
object RecoveryAttemptTracker {
    private const val PREFS = "vertisignage_bg"
    private const val KEY_ATTEMPT_ID = "recovery_attempt_id_pending"
    private const val KEY_STARTED_AT_MS = "recovery_attempt_started_at_ms"
    private const val KEY_AWAIT_VISIBLE = "recovery_attempt_await_visible"

    private fun prefs(ctx: Context) =
        (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            ctx.applicationContext.createDeviceProtectedStorageContext()
        } else {
            ctx.applicationContext
        }).getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * @param awaitVisible true when [CommandRelay.wakeApp] was invoked and we expect [MainActivity] resume.
     */
    fun beginAttempt(
        context: Context,
        attemptId: String,
        startedAtMs: Long,
        awaitVisible: Boolean,
    ) {
        try {
            prefs(context).edit()
                .putString(KEY_ATTEMPT_ID, attemptId)
                .putLong(KEY_STARTED_AT_MS, startedAtMs)
                .putBoolean(KEY_AWAIT_VISIBLE, awaitVisible)
                .apply()
        } catch (_: Throwable) {
        }
    }

    fun peekAttemptId(context: Context): String? =
        try {
            prefs(context).getString(KEY_ATTEMPT_ID, null)
        } catch (_: Throwable) {
            null
        }

    /**
     * If a pending attempt awaited visible UI, emit timing and clear. Call from [MainActivity.onPostResume].
     */
    fun consumeIfAwaitingVisible(
        context: Context,
        nowMs: Long,
    ): Pair<String, Long>? {
        return try {
            val p = prefs(context)
            if (!p.getBoolean(KEY_AWAIT_VISIBLE, false)) return null
            val id = p.getString(KEY_ATTEMPT_ID, null) ?: return null
            val started = p.getLong(KEY_STARTED_AT_MS, 0L)
            if (id.isEmpty() || started <= 0L) return null
            p.edit()
                .remove(KEY_ATTEMPT_ID)
                .remove(KEY_STARTED_AT_MS)
                .remove(KEY_AWAIT_VISIBLE)
                .apply()
            id to (nowMs - started).coerceAtLeast(0L)
        } catch (_: Throwable) {
            null
        }
    }

    fun clearAwaitVisible(context: Context) {
        try {
            prefs(context).edit().putBoolean(KEY_AWAIT_VISIBLE, false).apply()
        } catch (_: Throwable) {
        }
    }
}
