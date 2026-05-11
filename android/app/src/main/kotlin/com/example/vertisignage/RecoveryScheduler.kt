package com.example.vertisignage

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.example.vertisignage.BuildConfig
import androidx.work.BackoffPolicy
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

object RecoveryScheduler {
    private const val TAG = "VertiSignageBG"

    private const val UNIQUE_WORK_NOW = "vertisignage_recovery_now"
    private const val UNIQUE_WORK_PERIODIC = "vertisignage_recovery_periodic"

    private const val KEY_REASON = "reason"

    /** One PendingIntent for all recovery wakeup alarms — rescheduling replaces instead of stacking. */
    private const val RECOVERY_ALARM_REQUEST_CODE = 22100

    private const val NON_CRITICAL_COOLDOWN_MS = 45_000L

    private val lastNonCriticalEnqueueAt = AtomicLong(0L)

    /**
     * Enqueue a unique one-shot recovery attempt. Safe to call frequently.
     */
    fun enqueueNow(context: Context, reason: String) {
        val critical = isCriticalReason(reason)
        val nowMs = System.currentTimeMillis()
        if (!critical) {
            val last = lastNonCriticalEnqueueAt.get()
            if (last != 0L && nowMs - last < NON_CRITICAL_COOLDOWN_MS) {
                logDebugSkip("recovery_enqueue_now_throttled elapsedMs=${nowMs - last} reason=$reason")
                return
            }
        }

        try {
            val request =
                OneTimeWorkRequestBuilder<RecoveryWorker>()
                    .setInputData(workDataOf(KEY_REASON to reason))
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                    .build()
            val workPolicy = if (critical) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP
            WorkManager.getInstance(context)
                .enqueueUniqueWork(UNIQUE_WORK_NOW, workPolicy, request)
            scheduleAlarmFallback(context, "now:$reason", 60_000L)
            if (!critical) lastNonCriticalEnqueueAt.set(nowMs)
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
                RECOVERY_ALARM_REQUEST_CODE,
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

    /**
     * Only replace in-flight WM work when an immediate takeover is warranted (avoid GreedyScheduler churn).
     */
    internal fun isCriticalReason(reason: String): Boolean {
        val lower = reason.lowercase()
        if (lower.contains("native_crash")) return true
        // Prefer token boundaries so "reboot" does not match "boot".
        if (lower.startsWith("boot") || lower.contains(":boot")) return true
        if (lower.startsWith("push") || lower.contains(":push")) return true
        if (lower.startsWith("overlay") || lower.contains(":overlay")) return true
        // Schedule prewarm / exact / postcheck recovery must replace any in-flight stale work so
        // the new boundary's wake-and-render path takes priority over the previous boundary's tail.
        if (lower.startsWith("schedule") || lower.contains(":schedule")) return true
        return false
    }

    private fun logDebugSkip(message: String) {
        if (BuildConfig.DEBUG) Log.d(TAG, "$message source=RecoveryScheduler")
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
        when {
            level == Log.WARN -> Log.w(TAG, out)
            level == Log.ERROR -> Log.e(TAG, out)
            BuildConfig.DEBUG -> Log.d(TAG, out)
            else -> { /* Routine recovery noise omitted in release prod logcat */
            }
        }
    }
}
