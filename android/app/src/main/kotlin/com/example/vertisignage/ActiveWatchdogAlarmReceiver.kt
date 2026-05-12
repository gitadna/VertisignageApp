package com.example.vertisignage

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Self-rescheduling adaptive watchdog tick for Module 4.
 * Single PendingIntent slot ([REQUEST_CODE]) — re-arm replaces prior alarm.
 */
class ActiveWatchdogAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        try {
            PresentationRecoveryCoordinator.onWatchdogTick(
                context.applicationContext,
                "alarm_tick",
            )
        } catch (t: Throwable) {
            Log.w(TAG, "event=m4_watchdog_receive_failed msg=${t::class.java.simpleName}:${t.message}")
        }
    }

    companion object {
        private const val TAG = "VertiSignageBG"
        const val REQUEST_CODE = 22120
        private const val MIN_DELAY_MS = 10_000L

        fun arm(context: Context, delayMs: Long) {
            try {
                if (!WatchdogState.m4WatchdogEnabled(context)) return
                val am = context.getSystemService(AlarmManager::class.java) ?: return
                val triggerAt = System.currentTimeMillis() + delayMs.coerceAtLeast(MIN_DELAY_MS)
                val pi = pendingIntent(context)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                } else {
                    @Suppress("DEPRECATION")
                    am.set(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                }
                FleetTelemetry.log(
                    context.applicationContext,
                    "m4_watchdog_arm",
                    "delayMs=${delayMs.coerceAtLeast(MIN_DELAY_MS)}",
                )
            } catch (t: Throwable) {
                FleetTelemetry.log(
                    context.applicationContext,
                    "m4_alarm_arm_failed",
                    t::class.java.simpleName,
                )
            }
        }

        fun disarm(context: Context) {
            try {
                val am = context.getSystemService(AlarmManager::class.java) ?: return
                am.cancel(pendingIntent(context))
            } catch (_: Throwable) {
            }
        }

        private fun pendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, ActiveWatchdogAlarmReceiver::class.java)
            return PendingIntent.getBroadcast(
                context,
                REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
