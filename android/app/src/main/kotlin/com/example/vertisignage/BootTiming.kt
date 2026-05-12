package com.example.vertisignage

import android.content.Context
import android.os.Build

/**
 * Lightweight, device-protected timing trail for the boot -> first-frame path.
 *
 * Every write is best-effort and fully isolated from app behavior - if any storage call throws,
 * recovery logic must continue normally. Reads are exposed only for delta logging.
 *
 * Lives in the same `vertisignage_bg` SharedPreferences as [WatchdogState] / [BootReceiver]
 * so the existing device-protected storage permissions and boot survivability already apply.
 */
object BootTiming {
    private const val PREFS_NAME = "vertisignage_bg"

    private const val KEY_BOOT_RECEIVED_AT_MS = "boot_received_at_ms"
    private const val KEY_BOOT_FGS_STARTED_AT_MS = "boot_fgs_started_at_ms"
    private const val KEY_BOOT_WAKE_DISPATCHED_AT_MS = "boot_wake_dispatched_at_ms"
    private const val KEY_APP_ONCREATE_AT_MS = "app_oncreate_at_ms"
    private const val KEY_ENGINE_CACHED_AT_MS = "engine_cached_at_ms"
    private const val KEY_ACTIVITY_ONCREATE_AT_MS = "activity_oncreate_at_ms"
    private const val KEY_ACTIVITY_POSTRESUME_AT_MS = "activity_postresume_at_ms"

    fun markBootReceived(context: Context) = put(context, KEY_BOOT_RECEIVED_AT_MS)
    fun markBootFgsStarted(context: Context) = put(context, KEY_BOOT_FGS_STARTED_AT_MS)
    fun markBootWakeDispatched(context: Context) = put(context, KEY_BOOT_WAKE_DISPATCHED_AT_MS)
    fun markAppOnCreate(context: Context) = put(context, KEY_APP_ONCREATE_AT_MS)
    fun markEngineCached(context: Context) = put(context, KEY_ENGINE_CACHED_AT_MS)
    fun markActivityOnCreate(context: Context) = put(context, KEY_ACTIVITY_ONCREATE_AT_MS)
    fun markActivityPostResume(context: Context) = put(context, KEY_ACTIVITY_POSTRESUME_AT_MS)

    fun bootReceivedAtMs(context: Context): Long = get(context, KEY_BOOT_RECEIVED_AT_MS)
    fun appOnCreateAtMs(context: Context): Long = get(context, KEY_APP_ONCREATE_AT_MS)
    fun engineCachedAtMs(context: Context): Long = get(context, KEY_ENGINE_CACHED_AT_MS)
    fun activityOnCreateAtMs(context: Context): Long = get(context, KEY_ACTIVITY_ONCREATE_AT_MS)
    fun activityPostResumeAtMs(context: Context): Long = get(context, KEY_ACTIVITY_POSTRESUME_AT_MS)

    /** Returns `now - mark` in milliseconds, or -1 when [mark] is 0 / never recorded. */
    fun deltaSince(mark: Long, now: Long = System.currentTimeMillis()): Long =
        if (mark <= 0L) -1L else now - mark

    private fun put(context: Context, key: String) {
        try {
            prefs(context).edit()
                .putLong(key, System.currentTimeMillis())
                .apply()
        } catch (_: Throwable) {
            // Diagnostics must never fail boot recovery.
        }
    }

    private fun get(context: Context, key: String): Long = try {
        prefs(context).getLong(key, 0L)
    } catch (_: Throwable) {
        0L
    }

    private fun prefs(context: Context) = storageContext(context.applicationContext)
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun storageContext(context: Context): Context =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
}
