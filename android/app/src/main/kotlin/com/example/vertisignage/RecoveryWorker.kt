package com.example.vertisignage

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.example.vertisignage.BuildConfig
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
        WatchdogState.markServiceHeartbeat(applicationContext)

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

        if (PresentationRecoveryHints.shouldForceForeground(reason)) {
            ForegroundWakePolicy.syncPresentationState(applicationContext, true)
        }

        try {
            val nowMs = System.currentTimeMillis()
            val serviceStale = nowMs - WatchdogState.lastServiceHeartbeatMs(applicationContext) > SERVICE_STALE_MS
            val uiStale = nowMs - WatchdogState.lastUiHeartbeatMs(applicationContext) > UI_STALE_MS
            val serviceIntent = Intent(applicationContext, KioskForegroundService::class.java).apply {
                putExtra(BootReceiver.EXTRA_START_SOURCE, START_SOURCE_WORKER)
                putExtra(EXTRA_RECOVERY_REASON, reason)
                putExtra(EXTRA_FORCE_WAKE_UI, serviceStale || uiStale)
            }
            ContextCompat.startForegroundService(applicationContext, serviceIntent)
            if (serviceStale || uiStale) {
                if (ForegroundWakeGuard.allowRecoveryBringToForeground(applicationContext)) {
                    val wakeOk = CommandRelay.wakeApp(applicationContext)
                    if (!wakeOk) {
                        RecoveryScheduler.scheduleAlarmFallback(applicationContext, "worker_wake_failed:$reason", 15_000L)
                    }
                    log("worker_watchdog_recovery", "serviceStale=$serviceStale uiStale=$uiStale reason=$reason")
                } else {
                    log(
                        "worker_watchdog_recovery_skipped",
                        "presentation_idle_user_backdrop reason=$reason",
                        Log.INFO,
                    )
                }
            }
            RecoveryScheduler.scheduleAlarmFallback(applicationContext, "worker:$reason", 120_000L)
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
            else ->
                if (BuildConfig.DEBUG) {
                    Log.d(TAG, out)
                } else {
                    /* Routine worker logs omitted outside debug builds */
                }
        }
    }

    companion object {
        private const val TAG = "VertiSignageBG"

        private const val PREFS_NAME = "vertisignage_bg"
        private const val KEY_REASON = "reason"

        private const val START_SOURCE_WORKER = "workmanager"
        const val EXTRA_RECOVERY_REASON = "extra_recovery_reason"
        const val EXTRA_FORCE_WAKE_UI = "extra_force_wake_ui"
        private const val SERVICE_STALE_MS = 4 * 60_000L
        private const val UI_STALE_MS = 3 * 60_000L
    }
}

