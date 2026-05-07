package com.example.vertisignage

import android.content.Context
import android.os.Build

object WatchdogState {
    private const val PREFS_NAME = "vertisignage_bg"
    private const val KEY_SERVICE_HEARTBEAT_AT_MS = "service_heartbeat_at_ms"
    private const val KEY_UI_HEARTBEAT_AT_MS = "ui_heartbeat_at_ms"
    private const val KEY_NATIVE_CRASH_AT_MS = "native_crash_at_ms"
    private const val KEY_NATIVE_CRASH_REASON = "native_crash_reason"

    fun markServiceHeartbeat(context: Context) = prefs(context).edit()
        .putLong(KEY_SERVICE_HEARTBEAT_AT_MS, System.currentTimeMillis())
        .apply()

    fun markUiHeartbeat(context: Context) = prefs(context).edit()
        .putLong(KEY_UI_HEARTBEAT_AT_MS, System.currentTimeMillis())
        .apply()

    fun lastServiceHeartbeatMs(context: Context): Long =
        prefs(context).getLong(KEY_SERVICE_HEARTBEAT_AT_MS, 0L)

    fun lastUiHeartbeatMs(context: Context): Long =
        prefs(context).getLong(KEY_UI_HEARTBEAT_AT_MS, 0L)

    fun recordNativeCrash(context: Context, reason: String) {
        prefs(context).edit()
            .putLong(KEY_NATIVE_CRASH_AT_MS, System.currentTimeMillis())
            .putString(KEY_NATIVE_CRASH_REASON, reason)
            .apply()
    }

    private fun prefs(context: Context) = storageContext(context)
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun storageContext(context: Context): Context =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
}
