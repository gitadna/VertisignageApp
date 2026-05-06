package com.example.vertisignage

import android.content.Context
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
            WorkManager.getInstance(context)
                .enqueueUniqueWork(UNIQUE_WORK_NOW, ExistingWorkPolicy.KEEP, request)
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
            log("recovery_ensure_periodic", "ok reason=$reason")
        } catch (t: Throwable) {
            log("recovery_ensure_periodic", "failed ${t::class.java.simpleName}:${t.message} reason=$reason", Log.WARN)
        }
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

