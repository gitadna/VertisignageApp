package com.example.vertisignage

import android.content.Context
import android.os.Build
import android.util.Log

/**
 * Structured fleet diagnostics (local logcat). Pair with remote log upload from Flutter when needed.
 */
object FleetTelemetry {
    private const val TAG = "VertiSignageTelemetry"

    fun log(
        context: Context,
        event: String,
        detail: String? = null,
    ) {
        val msg =
            buildString {
                append("event=").append(event)
                append(" api=").append(Build.VERSION.SDK_INT)
                append(" manufacturer=").append(Build.MANUFACTURER ?: "unknown")
                if (!detail.isNullOrBlank()) {
                    append(" detail=").append(detail)
                }
            }
        Log.i(TAG, msg)
    }
}
