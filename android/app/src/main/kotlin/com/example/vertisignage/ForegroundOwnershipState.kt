package com.example.vertisignage

import android.content.Context
import android.os.Build

/**
 * Serialized foreground-recovery ownership + dedupe window for Module 4.
 * Stored in device-protected storage so boot-time paths can read it.
 */
object ForegroundOwnershipState {
    private const val PREFS = "vertisignage_fg_owner"

    private const val KEY_OWNER = "current_foreground_owner"
    private const val KEY_REASON = "owner_reason"
    private const val KEY_ACQUIRED_MS = "owner_acquired_at_ms"
    private const val KEY_EXPIRY_MS = "owner_expiry_ms"
    private const val KEY_GENERATION = "owner_generation"
    private const val KEY_WINDOW_ID = "recovery_window_id"
    private const val KEY_WINDOW_EXPIRY_MS = "recovery_window_expiry_ms"
    private const val KEY_OWNER_PRIORITY = "owner_priority"

    private fun prefs(ctx: Context) =
        storageCtx(ctx.applicationContext).getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun storageCtx(context: Context): Context =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }

    fun ownerSnapshot(context: Context): Map<String, Any?> {
        return try {
            val p = prefs(context)
            mapOf(
                "owner" to p.getString(KEY_OWNER, null),
                "reason" to p.getString(KEY_REASON, null),
                "acquiredAtMs" to p.getLong(KEY_ACQUIRED_MS, 0L),
                "expiryMs" to p.getLong(KEY_EXPIRY_MS, 0L),
                "generation" to p.getLong(KEY_GENERATION, 0L),
                "windowId" to p.getString(KEY_WINDOW_ID, null),
                "windowExpiryMs" to p.getLong(KEY_WINDOW_EXPIRY_MS, 0L),
            )
        } catch (_: Throwable) {
            emptyMap()
        }
    }

    /**
     * Returns true if [owner] acquired or extended. Higher [priority] wins over lower until expiry.
     */
    fun tryAcquireOwner(
        context: Context,
        owner: String,
        reason: String,
        ttlMs: Long,
        priority: Int,
    ): Boolean {
        return try {
            val p = prefs(context)
            val now = System.currentTimeMillis()
            val cur = p.getString(KEY_OWNER, null)
            val exp = p.getLong(KEY_EXPIRY_MS, 0L)
            val curPri = p.getInt(KEY_OWNER_PRIORITY, 0)
            if (cur != null && now < exp && priority < curPri) {
                return false
            }
            val gen = p.getLong(KEY_GENERATION, 0L) + 1L
            p.edit()
                .putString(KEY_OWNER, owner)
                .putString(KEY_REASON, reason)
                .putLong(KEY_ACQUIRED_MS, now)
                .putLong(KEY_EXPIRY_MS, now + ttlMs.coerceAtLeast(5_000L))
                .putLong(KEY_GENERATION, gen)
                .putInt(KEY_OWNER_PRIORITY, priority)
                .apply()
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun releaseOwnerIfMatches(context: Context, owner: String) {
        try {
            val p = prefs(context)
            if (p.getString(KEY_OWNER, null) == owner) {
                p.edit()
                    .remove(KEY_OWNER)
                    .remove(KEY_REASON)
                    .putLong(KEY_EXPIRY_MS, 0L)
                    .remove(KEY_OWNER_PRIORITY)
                    .apply()
            }
        } catch (_: Throwable) {
        }
    }

    /** Single coordinated execution slot (prevents overlapping ladder runs). */
    fun tryBeginRecoveryWindow(context: Context, windowId: String, ttlMs: Long): Boolean {
        return try {
            val p = prefs(context)
            val now = System.currentTimeMillis()
            val until = p.getLong(KEY_WINDOW_EXPIRY_MS, 0L)
            val wid = p.getString(KEY_WINDOW_ID, null)
            if (wid == windowId && now < until) {
                return false
            }
            if (now < until && wid != null) {
                return false
            }
            p.edit()
                .putString(KEY_WINDOW_ID, windowId)
                .putLong(KEY_WINDOW_EXPIRY_MS, now + ttlMs.coerceIn(3_000L, 30_000L))
                .apply()
            true
        } catch (_: Throwable) {
            true
        }
    }

    fun endRecoveryWindow(context: Context) {
        try {
            prefs(context).edit()
                .remove(KEY_WINDOW_ID)
                .putLong(KEY_WINDOW_EXPIRY_MS, 0L)
                .apply()
        } catch (_: Throwable) {
        }
    }

    /** Priority scale: overlay/emergency highest. */
    const val PRIORITY_OVERLAY = 100
    const val PRIORITY_SCHEDULE = 80
    const val PRIORITY_PUSH = 75
    const val PRIORITY_WATCHDOG = 50
    const val PRIORITY_BOOT = 40
    const val PRIORITY_GENERIC = 10
}
