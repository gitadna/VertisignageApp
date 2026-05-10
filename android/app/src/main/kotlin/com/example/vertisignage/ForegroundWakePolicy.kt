package com.example.vertisignage

import android.content.Context
import android.os.Build

/**
 * Persisted foreground-wake hints from Flutter ([presentation] state) plus native backdrop hint
 * when the user leaves VertiSignage ([onUserLeaveHint]) in relaxed (non-kiosk-lock) deployments.
 *
 * Stored in device-protected storage so early boot receivers can still read sane defaults.
 */
object ForegroundWakePolicy {
    private const val PREFS_NAME = "vertisignage_fg_wake"
    private const val KEY_RELAXED_TEACHER_MODE = "relaxed_teacher_mode"
    private const val KEY_PRESENTATION_WANTS_FG = "presentation_wants_foreground"
    private const val KEY_LAST_PRESENTATION_SYNC_MS = "last_presentation_sync_ms"
    private const val KEY_USER_BACKDROP_SINCE_MS = "user_backdrop_since_ms"

    private fun prefs(context: Context) =
        storageContext(context).getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun storageContext(context: Context): Context =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }

    /**
     * When false (default), recovery paths behave like legacy unattended-kiosk installs.
     * Flutter sets true when strict kiosk lock-task is disabled (teacher / classroom mode).
     */
    fun setRelaxedTeacherMode(context: Context, relaxed: Boolean) {
        prefs(context.applicationContext).edit().putBoolean(KEY_RELAXED_TEACHER_MODE, relaxed).apply()
    }

    fun isRelaxedTeacherMode(context: Context): Boolean =
        prefs(context.applicationContext).getBoolean(KEY_RELAXED_TEACHER_MODE, false)

    fun syncPresentationState(
        context: Context,
        wantsForeground: Boolean,
    ) {
        val ctx = context.applicationContext
        val now = System.currentTimeMillis()
        prefs(ctx).edit()
            .putBoolean(KEY_PRESENTATION_WANTS_FG, wantsForeground)
            .putLong(KEY_LAST_PRESENTATION_SYNC_MS, now)
            .apply()
    }

    fun presentationWantsForeground(context: Context): Boolean =
        prefs(context.applicationContext).getBoolean(KEY_PRESENTATION_WANTS_FG, false)

    fun lastPresentationSyncMs(context: Context): Long =
        prefs(context.applicationContext).getLong(KEY_LAST_PRESENTATION_SYNC_MS, 0L)

    fun markUserBackdropHint(context: Context) {
        prefs(context.applicationContext).edit().putLong(KEY_USER_BACKDROP_SINCE_MS, System.currentTimeMillis()).apply()
    }

    fun clearUserBackdropHint(context: Context) {
        prefs(context.applicationContext).edit().putLong(KEY_USER_BACKDROP_SINCE_MS, 0L).apply()
    }

    /** True when the teacher pressed Home / task switch ([onUserLeaveHint]). */
    fun userBackdropActive(context: Context): Boolean =
        prefs(context.applicationContext).getLong(KEY_USER_BACKDROP_SINCE_MS, 0L) > 0L
}

/**
 * When native recovery work runs for these reasons, pre-sync presentation intent so
 * [ForegroundWakeGuard] does not suppress legitimate push or schedule-driven foregrounding.
 */
object PresentationRecoveryHints {
    fun shouldForceForeground(reason: String): Boolean {
        val r = reason.lowercase()
        if (r.contains("push")) return true
        if (r.contains("overlay")) return true
        if (r.contains("announcement")) return true
        if (r.contains("schedule_exact")) return true
        if (r.contains("schedule_boundary")) return true
        if (r.contains("native_crash")) return true
        return false
    }
}
