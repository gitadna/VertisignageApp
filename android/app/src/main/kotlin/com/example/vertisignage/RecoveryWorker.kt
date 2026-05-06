package com.example.vertisignage

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

class RecoveryWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val reason = inputData.getString(KEY_REASON) ?: "unknown"
        log("worker_run", "begin reason=$reason")

        val storageContext =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                applicationContext.createDeviceProtectedStorageContext()
            else applicationContext
        val prefs = storageContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        val firstLaunchCompleted = prefs.getBoolean(BootReceiver.KEY_FIRST_LAUNCH_COMPLETED, false)
        if (!firstLaunchCompleted) {
            prefs.edit()
                .putBoolean(BootReceiver.KEY_PENDING_BOOT_RECOVERY, true)
                .putString(BootReceiver.KEY_PENDING_BOOT_RECOVERY_REASON, "worker_first_launch_missing:$reason")
                .apply()
            log("worker_skip", "first_launch_not_completed reason=$reason", Log.WARN)
            return Result.success()
        }

        try {
            val serviceIntent = Intent(applicationContext, KioskForegroundService::class.java).apply {
                putExtra(BootReceiver.EXTRA_START_SOURCE, START_SOURCE_WORKER)
                putExtra(EXTRA_RECOVERY_REASON, reason)
            }
            ContextCompat.startForegroundService(applicationContext, serviceIntent)
            log("worker_start_fgs", "requested reason=$reason")
        } catch (t: Throwable) {
            prefs.edit()
                .putBoolean(BootReceiver.KEY_PENDING_BOOT_RECOVERY, true)
                .putString(BootReceiver.KEY_PENDING_BOOT_RECOVERY_REASON, "worker_fgs_start_blocked:${t::class.java.simpleName}")
                .apply()
            log("worker_start_fgs_failed", "${t::class.java.simpleName}:${t.message} reason=$reason", Log.WARN)
            // Retrying later can help in transient restriction windows.
            return Result.retry()
        }

        return Result.success()
    }

    private fun log(event: String, msg: String, level: Int = Log.INFO) {
        val out =
            buildString {
                append("event=").append(event)
                append(" source=RecoveryWorker")
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

    companion object {
        private const val TAG = "VertiSignageBG"

        private const val PREFS_NAME = "vertisignage_bg"
        private const val KEY_REASON = "reason"

        private const val START_SOURCE_WORKER = "workmanager"
        const val EXTRA_RECOVERY_REASON = "extra_recovery_reason"
    }
}

