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
        try {
            ContextCompat.startForegroundService(
                context,
                Intent(context, KioskForegroundService::class.java).apply {
                    putExtra(BootReceiver.EXTRA_START_SOURCE, START_SOURCE_ALARM)
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
