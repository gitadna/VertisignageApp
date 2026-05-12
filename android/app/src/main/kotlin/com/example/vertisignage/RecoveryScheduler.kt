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

    /**
     * Distinct request codes for the boot staggered fallback chain. Each independently armed so
     * a single OEM-blocked wake cannot strand the app: any later alarm in the chain will still
     * deliver. Request codes are stable and reused across boots so [FLAG_UPDATE_CURRENT] makes
     * re-arming idempotent.
     */
    private val BOOT_STAGGERED_REQUEST_CODES = intArrayOf(22101, 22102, 22103, 22104, 22105)
    private val BOOT_STAGGERED_DELAYS_MS = longArrayOf(
        5_000L,
        15_000L,
        45_000L,
        90_000L,
        180_000L,
    )

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
        // Legacy single-slot fallback: callers that don't need staggering retain the original
        // shared request code so re-arming with a closer delay replaces in place.
        armAlarmFallback(
            context = context,
            reason = reason,
            delayMs = delayMs,
            requestCode = RECOVERY_ALARM_REQUEST_CODE,
            minimumDelayMs = 15_000L,
            stagger = false,
        )
    }

    /**
     * Arms the boot recovery fallback chain at +5/+15/+45/+90/+180 seconds. Each window uses a
     * dedicated request code so they coexist instead of replacing each other; combined with
     * [PendingIntent.FLAG_UPDATE_CURRENT] this stays idempotent across repeat boots.
     *
     * Designed for OEM firmware (Xiaomi/Vivo/Realme/TVs/signage panels) that may throttle the
     * first one or two wake attempts after BOOT_COMPLETED. Even if the FGS path in
     * [BootReceiver] is blocked, a later alarm will still deliver an ACTION_WAKE through
     * [RecoveryAlarmReceiver].
     */
    fun scheduleBootStaggeredFallbacks(context: Context, reason: String) {
        for ((index, delayMs) in BOOT_STAGGERED_DELAYS_MS.withIndex()) {
            val taggedReason = "boot_staggered_${delayMs / 1000}s:$reason"
            armAlarmFallback(
                context = context,
                reason = taggedReason,
                delayMs = delayMs,
                requestCode = BOOT_STAGGERED_REQUEST_CODES[index],
                // Permit short delays (5s) for the first slot; this only runs from boot recovery.
                minimumDelayMs = 0L,
                stagger = true,
            )
        }
        log("recovery_boot_staggered_fallbacks", "armed slots=${BOOT_STAGGERED_DELAYS_MS.size} reason=$reason")
    }

    private fun armAlarmFallback(
        context: Context,
        reason: String,
        delayMs: Long,
        requestCode: Int,
        minimumDelayMs: Long,
        stagger: Boolean,
    ) {
        try {
            val am = context.getSystemService(AlarmManager::class.java) ?: return
            val triggerAtMs = System.currentTimeMillis() + delayMs.coerceAtLeast(minimumDelayMs)
            val intent = Intent(context, RecoveryAlarmReceiver::class.java).apply {
                putExtra(RecoveryAlarmReceiver.EXTRA_REASON, reason)
            }
            val pi = PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
            } else {
                @Suppress("DEPRECATION")
                am.set(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
            }
            log(
                event = if (stagger) "recovery_alarm_fallback_staggered" else "recovery_alarm_fallback",
                msg = "scheduled reason=$reason delayMs=$delayMs requestCode=$requestCode",
            )
        } catch (t: Throwable) {
            log(
                event = if (stagger) "recovery_alarm_fallback_staggered" else "recovery_alarm_fallback",
                msg = "failed ${t::class.java.simpleName}:${t.message} reason=$reason requestCode=$requestCode",
                level = Log.WARN,
            )
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
