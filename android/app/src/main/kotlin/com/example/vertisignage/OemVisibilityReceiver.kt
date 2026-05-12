package com.example.vertisignage

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Debounced visibility hooks for OEM launcher / screen transitions.
 */
class OemVisibilityReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        try {
            val action = intent?.action ?: return
            if (action != Intent.ACTION_SCREEN_ON && action != Intent.ACTION_USER_PRESENT) {
                return
            }
            val now = System.currentTimeMillis()
            val last = synchronized(LOCK) {
                val prev = lastNotifyAtMs
                lastNotifyAtMs = now
                prev
            }
            if (now - last < DEBOUNCE_MS) {
                FleetTelemetry.log(
                    context.applicationContext,
                    "m4_oem_visibility_debounced",
                    action,
                )
                return
            }
            PresentationRecoveryCoordinator.notifyTrigger(
                context.applicationContext,
                "oem_visibility:$action",
            )
        } catch (t: Throwable) {
            Log.w(TAG, "event=m4_oem_visibility_failed msg=${t::class.java.simpleName}:${t.message}")
        }
    }

    companion object {
        private const val TAG = "VertiSignageBG"
        private const val DEBOUNCE_MS = 2_500L
        private val LOCK = Any()
        private var lastNotifyAtMs = 0L
    }
}
