package com.example.vertisignage

import android.content.Context

/**
 * Gates watchdog / alarm-driven UI recovery so relaxed teacher tablets stay in the background
 * when nobody is broadcasting content worth stealing focus.
 */
object ForegroundWakeGuard {
    /**
     * If Flutter has gone quiet (process dead, engine wedged), err on the side of restoring UI.
     */
    private const val STALE_FLUTTER_PRESENTATION_SYNC_MS = 120_000L

    /** Used by watchdog / task-removed alarm-style recovery. */
    fun allowRecoveryBringToForeground(context: Context): Boolean {
        if (!ForegroundWakePolicy.isRelaxedTeacherMode(context.applicationContext)) {
            return true
        }
        val appCtx = context.applicationContext
        val now = System.currentTimeMillis()
        val lastSync = ForegroundWakePolicy.lastPresentationSyncMs(appCtx)
        if (lastSync <= 0L || now - lastSync > STALE_FLUTTER_PRESENTATION_SYNC_MS) {
            return true
        }
        if (ForegroundWakePolicy.presentationWantsForeground(appCtx)) {
            return true
        }
        if (!ForegroundWakePolicy.userBackdropActive(appCtx)) {
            return true
        }
        return false
    }

    /**
     * Schedule-boundary wake always overrides relaxed-teacher backdrop gating: scheduled playback
     * is an explicit operator intent. Kept as an explicit method so the override path is auditable
     * and so any future tightening (e.g. quiet-hours policy) lives in one place without affecting
     * [allowRecoveryBringToForeground].
     */
    @Suppress("UNUSED_PARAMETER")
    fun allowScheduleBoundaryWake(context: Context): Boolean = true
}
