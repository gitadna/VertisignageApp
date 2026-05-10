package com.example.vertisignage

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Schedules a single exact RTC alarm for the next playlist boundary. Requires [SCHEDULE_EXACT_ALARM]
 * on Android 12+ when the app is not on the allowlist for exact alarms.
 */
object PlaylistScheduleAlarm {
    private const val TAG = "VertiSignageBG"
    private const val REQUEST_CODE = 55821

    fun canScheduleExactAlarms(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val am = context.getSystemService(AlarmManager::class.java) ?: return false
        return am.canScheduleExactAlarms()
    }

    /**
     * @return true if the alarm was scheduled, false if exact alarms are unavailable (use Dart timer fallback).
     */
    fun schedule(context: Context, triggerAtEpochMs: Long): Boolean {
        val app = context.applicationContext
        val am = app.getSystemService(AlarmManager::class.java) ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
            FleetTelemetry.log(app, "schedule_boundary_alarm_skipped", "cannot_schedule_exact")
            return false
        }
        val now = System.currentTimeMillis()
        // Avoid racing the Dart boundary timer; stay slightly ahead of the boundary when possible.
        val triggerAt = maxOf(triggerAtEpochMs, now + 3_000L)
        cancel(app)
        val intent = Intent(app, ScheduleBoundaryAlarmReceiver::class.java)
        val pi =
            PendingIntent.getBroadcast(
                app,
                REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            } else {
                @Suppress("DEPRECATION")
                am.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            }
            FleetTelemetry.log(app, "schedule_boundary_alarm_scheduled", "atMs=$triggerAt")
            return true
        } catch (t: Throwable) {
            Log.w(TAG, "event=schedule_boundary_alarm_failed msg=${t::class.java.simpleName}:${t.message}")
            FleetTelemetry.log(app, "schedule_boundary_alarm_failed", t::class.java.simpleName)
            return false
        }
    }

    fun cancel(context: Context) {
        val app = context.applicationContext
        val am = app.getSystemService(AlarmManager::class.java) ?: return
        val intent = Intent(app, ScheduleBoundaryAlarmReceiver::class.java)
        val pi =
            PendingIntent.getBroadcast(
                app,
                REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        try {
            am.cancel(pi)
        } catch (_: Throwable) {
            // ignore
        }
    }
}
