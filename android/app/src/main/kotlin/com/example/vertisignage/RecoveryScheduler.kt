package com.example.vertisignage

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit

object RecoveryScheduler {
    private const val TAG = "VertiSignageBG"

    private const val UNIQUE_WORK_NOW = "vertisignage_recovery_now"
    private const val UNIQUE_WORK_PERIODIC = "vertisignage_recovery_periodic"

    private const val KEY_REASON = "reason"
    /**
     * Enqueue a unique one-shot recovery attempt. Safe to call frequently.
     */
    fun enqueueNow(context: Context, reason: String) {
        try {
            val request =
                OneTimeWorkRequestBuilder<RecoveryWorker>()
                    .setInputData(workDataOf(KEY_REASON to reason))
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                    .build()
            val workPolicy = if (isCriticalReason(reason)) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP
            WorkManager.getInstance(context)
                .enqueueUniqueWork(UNIQUE_WORK_NOW, workPolicy, request)
            scheduleAlarmFallback(context, "now:$reason", 60_000L)
            log("recovery_enqueue_now", "ok reason=$reason")
        } catch (t: Throwable) {
            log("recovery_enqueue_now", "failed ${t::class.java.simpleName}:${t.message} reason=$reason", Log.WARN)
        }
    }

    /**
     * Ensure a periodic recovery heartbeat exists (minimum 15 minutes).
     */
    fun ensurePeriodic(context: Context, reason: String) {
        try {
            val request =
                PeriodicWorkRequestBuilder<RecoveryWorker>(15, TimeUnit.MINUTES)
                    .setInputData(workDataOf(KEY_REASON to "periodic:$reason"))
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                    .build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(UNIQUE_WORK_PERIODIC, ExistingPeriodicWorkPolicy.KEEP, request)
            scheduleAlarmFallback(context, "periodic:$reason", 5 * 60_000L)
            log("recovery_ensure_periodic", "ok reason=$reason")
        } catch (t: Throwable) {
            log("recovery_ensure_periodic", "failed ${t::class.java.simpleName}:${t.message} reason=$reason", Log.WARN)
        }
    }

    fun scheduleAlarmFallback(context: Context, reason: String, delayMs: Long) {
        try {
            val am = context.getSystemService(AlarmManager::class.java) ?: return
            val triggerAtMs = System.currentTimeMillis() + delayMs.coerceAtLeast(15_000L)
            val intent = Intent(context, RecoveryAlarmReceiver::class.java).apply {
                putExtra(RecoveryAlarmReceiver.EXTRA_REASON, reason)
            }
            val pi = PendingIntent.getBroadcast(
                context,
                alarmRequestCode(reason),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
            } else {
                @Suppress("DEPRECATION")
                am.set(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
            }
            log("recovery_alarm_fallback", "scheduled reason=$reason delayMs=$delayMs")
        } catch (t: Throwable) {
            log("recovery_alarm_fallback", "failed ${t::class.java.simpleName}:${t.message} reason=$reason", Log.WARN)
        }
    }

    private fun isCriticalReason(reason: String): Boolean {
        val lower = reason.lowercase()
        return lower.contains("boot") ||
            lower.contains("alarm") ||
            lower.contains("push") ||
            lower.contains("overlay") ||
            lower.contains("native_crash")
    }

    private fun alarmRequestCode(reason: String): Int {
        val seed = reason.hashCode().toLong().let { kotlin.math.abs(it) }
        return 22000 + (seed % 400).toInt()
    }

    private fun log(event: String, msg: String, level: Int = Log.INFO) {
        val out =
            buildString {
                append("event=").append(event)
                append(" source=RecoveryScheduler")
                append(" api=").append(Build.VERSION.SDK_INT)
                append(" manufacturer=").append(Build.MANUFACTURER ?: "unknown")
                append(" msg=").append(msg)
            }
        when (level) {
            Log.WARN -> Log.w(TAG, out)
            Log.ERROR -> Log.e(TAG, out)
            else -> Log.i(TAG, out)
        }
    }
}

