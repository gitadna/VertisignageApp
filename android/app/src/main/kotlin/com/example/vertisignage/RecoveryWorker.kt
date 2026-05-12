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
        // Soak telemetry: piggyback on the existing 15-minute periodic worker so 24h/48h fleet
        // diagnostics arrive without spinning a new schedule. Non-periodic invocations skip
        // this so we don't spam every push/boot/schedule recovery with the same payload.
        if (reason.startsWith("periodic")) {
            emitSoakHeartbeat(reason)
        }

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

        val nowMsEarly = System.currentTimeMillis()
        val serviceStaleEarly =
            nowMsEarly - WatchdogState.lastServiceHeartbeatMs(applicationContext) > SERVICE_STALE_MS
        val uiStaleEarly =
            nowMsEarly - WatchdogState.lastUiHeartbeatMs(applicationContext) > UI_STALE_MS
        val staleEarly = serviceStaleEarly || uiStaleEarly
        val emitRecoveryAnalytics =
            !reason.startsWith("periodic") || staleEarly
        val attemptId =
            if (emitRecoveryAnalytics) RecoveryAnalyticsEmitter.newAttemptId() else null
        val triggerSource = RecoveryTriggerTaxonomy.classify(reason)
        if (attemptId != null) {
            RecoveryAnalyticsEmitter.emitRecoveryStarted(
                applicationContext,
                attemptId,
                triggerSource,
                reason,
                "workmanager_recovery",
            )
        }

        try {
            val nowMs = System.currentTimeMillis()
            val serviceStale = nowMs - WatchdogState.lastServiceHeartbeatMs(applicationContext) > SERVICE_STALE_MS
            val uiStale = nowMs - WatchdogState.lastUiHeartbeatMs(applicationContext) > UI_STALE_MS
            val serviceIntent = Intent(applicationContext, KioskForegroundService::class.java).apply {
                putExtra(BootReceiver.EXTRA_START_SOURCE, START_SOURCE_WORKER)
                putExtra(EXTRA_RECOVERY_REASON, reason)
                putExtra(EXTRA_FORCE_WAKE_UI, serviceStale || uiStale)
                if (attemptId != null) {
                    putExtra(RecoveryAnalyticsEmitter.EXTRA_RECOVERY_ATTEMPT_ID, attemptId)
                }
            }
            ContextCompat.startForegroundService(applicationContext, serviceIntent)
            if (serviceStale || uiStale) {
                if (ForegroundWakeGuard.allowRecoveryBringToForeground(applicationContext)) {
                    val bring =
                        RecoveryWakeRouter.shouldBringActivityToForeground(
                            applicationContext,
                            forceUiWakeIntent = false,
                            forceWakeUiFromWorker = true,
                            startSource = START_SOURCE_WORKER,
                        )
                    if (bring) {
                        val wakeOk = CommandRelay.wakeApp(applicationContext)
                        if (!wakeOk) {
                            RecoveryScheduler.scheduleAlarmFallback(applicationContext, "worker_wake_failed:$reason", 15_000L)
                            if (attemptId != null) {
                                RecoveryAnalyticsEmitter.emitRecoveryCompleted(
                                    applicationContext,
                                    attemptId,
                                    triggerSource,
                                    "wakeApp",
                                    RecoveryAnalyticsEmitter.RESULT_FAILED,
                                    timeToVisibleMs = null,
                                    timeToBackgroundRuntimeMs = null,
                                    legacyReason = reason,
                                )
                            }
                        } else if (attemptId != null) {
                            RecoveryAttemptTracker.beginAttempt(
                                applicationContext,
                                attemptId,
                                nowMs,
                                awaitVisible = true,
                            )
                        }
                    } else if (attemptId != null) {
                        RecoveryAnalyticsEmitter.emitRecoveryCompleted(
                            applicationContext,
                            attemptId,
                            triggerSource,
                            "workmanager_recovery",
                            RecoveryAnalyticsEmitter.RESULT_SUCCESS,
                            timeToVisibleMs = null,
                            timeToBackgroundRuntimeMs = null,
                            legacyReason = "worker_stale_skipped_no_presentation_demand reason=$reason",
                        )
                    }
                    log(
                        "worker_watchdog_recovery",
                        "serviceStale=$serviceStale uiStale=$uiStale reason=$reason bring=$bring",
                    )
                } else if (attemptId != null) {
                    RecoveryAnalyticsEmitter.emitRecoveryCompleted(
                        applicationContext,
                        attemptId,
                        triggerSource,
                        "workmanager_recovery",
                        RecoveryAnalyticsEmitter.RESULT_SUPPRESSED,
                        timeToVisibleMs = null,
                        timeToBackgroundRuntimeMs = null,
                        legacyReason = "foreground_wake_guard reason=$reason",
                    )
                    log(
                        "worker_watchdog_recovery_skipped",
                        "presentation_idle_user_backdrop reason=$reason",
                        Log.INFO,
                    )
                }
            } else if (attemptId != null) {
                RecoveryAnalyticsEmitter.emitRecoveryCompleted(
                    applicationContext,
                    attemptId,
                    triggerSource,
                    "foreground_service",
                    RecoveryAnalyticsEmitter.RESULT_SUCCESS,
                    timeToVisibleMs = null,
                    timeToBackgroundRuntimeMs = null,
                    legacyReason = "worker_not_stale reason=$reason",
                )
            }
            RecoveryScheduler.scheduleAlarmFallback(applicationContext, "worker:$reason", 120_000L)
            log("worker_start_fgs", "requested reason=$reason")
        } catch (t: Throwable) {
            if (attemptId != null) {
                RecoveryAnalyticsEmitter.emitRecoveryCompleted(
                    applicationContext,
                    attemptId,
                    triggerSource,
                    "workmanager_recovery",
                    RecoveryAnalyticsEmitter.RESULT_FAILED,
                    timeToVisibleMs = null,
                    timeToBackgroundRuntimeMs = null,
                    legacyReason = "worker_fgs_start_blocked:${t::class.java.simpleName}",
                )
            }
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

    private fun emitSoakHeartbeat(reason: String) {
        try {
            val app = applicationContext
            val now = System.currentTimeMillis()
            val appStart = BootTiming.appOnCreateAtMs(app)
            val processUptimeMs = if (appStart > 0L) now - appStart else -1L
            val loopRecent = RecoveryLoopGuard.recentCount(app)
            val inLoop = RecoveryLoopGuard.inLoop(app)
            val engineCached = VertiSignageApp.cachedEngine() != null
            val serviceHbAgeMs = ageMs(now, WatchdogState.lastServiceHeartbeatMs(app))
            val uiHbAgeMs = ageMs(now, WatchdogState.lastUiHeartbeatMs(app))
            FleetTelemetry.log(
                app,
                "soak_heartbeat",
                "reason=$reason processUptimeMs=$processUptimeMs " +
                    "loopRecent=$loopRecent inLoop=$inLoop engineCached=$engineCached " +
                    "serviceHbAgeMs=$serviceHbAgeMs uiHbAgeMs=$uiHbAgeMs",
            )
        } catch (_: Throwable) {
            // Diagnostics must never disturb recovery.
        }
    }

    private fun ageMs(now: Long, ts: Long): Long =
        if (ts <= 0L) -1L else (now - ts).coerceAtLeast(0L)

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

