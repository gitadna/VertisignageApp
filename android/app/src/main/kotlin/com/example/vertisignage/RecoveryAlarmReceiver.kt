package com.example.vertisignage

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

class RecoveryAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val reason = intent?.getStringExtra(EXTRA_REASON) ?: "alarm"
        RecoveryScheduler.enqueueNow(context, "alarm:$reason")
        // Boot-staggered fallbacks must explicitly identify as boot-source so the FGS can log
        // boot wake deltas via BootTiming and emit boot-prefixed diagnostics.
        val isBootRecovery = reason.startsWith("boot") || reason.contains(":boot")
        if (isBootRecovery) {
            BootTiming.markBootWakeDispatched(context)
            FleetTelemetry.log(context, "boot_wake_dispatched", "reason=$reason")
        }
        try {
            val startSource = if (isBootRecovery) BootReceiver.START_SOURCE_BOOT else START_SOURCE_ALARM
            ContextCompat.startForegroundService(
                context,
                Intent(context, KioskForegroundService::class.java).apply {
                    // ACTION_WAKE routes the wake through the BAL-safe foreground-service path
                    // (Android 12+ forbids receiver-driven startActivity in most contexts).
                    action = KioskForegroundService.ACTION_WAKE
                    putExtra(BootReceiver.EXTRA_START_SOURCE, startSource)
                    putExtra(RecoveryWorker.EXTRA_RECOVERY_REASON, reason)
                },
            )
        } catch (t: Throwable) {
            Log.w(TAG, "event=alarm_fgs_start_failed source=RecoveryAlarmReceiver reason=$reason msg=${t::class.java.simpleName}:${t.message}")
        }
        // Do not elevate the Activity here; [RecoveryWorker] applies [ForegroundWakeGuard] when needed.
    }

    companion object {
        const val EXTRA_REASON = "extra_reason"
        private const val START_SOURCE_ALARM = "alarm"
        private const val TAG = "VertiSignageBG"
    }
}
