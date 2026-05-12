package com.example.vertisignage

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Three-phase alarm receiver. Phase comes from the [PlaylistScheduleAlarm] PendingIntent extras:
 *   - prewarm  : warm FGS + activity ~10s before boundary so first frame can render at target.
 *   - exact    : boundary itself; wake activity with override of relaxed-teacher backdrop.
 *   - postcheck: verify UI heartbeat bumped after target; escalate to restartApp if not.
 *
 * Backwards compatible: if phase extra missing (legacy schedule call), behave like the legacy
 * single exact alarm (preserve all prior side-effects).
 */
class ScheduleBoundaryAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val app = context.applicationContext
        val phase = intent?.getStringExtra(PlaylistScheduleAlarm.EXTRA_PHASE)
            ?: PlaylistScheduleAlarm.PHASE_EXACT
        val targetMs = intent?.getLongExtra(PlaylistScheduleAlarm.EXTRA_TARGET_MS, 0L) ?: 0L
        val now = System.currentTimeMillis()
        val deltaMs = if (targetMs > 0L) now - targetMs else 0L

        FleetTelemetry.log(
            app,
            "schedule_alarm_fired",
            "phase=$phase deltaMs=$deltaMs targetMs=$targetMs",
        )

        when (phase) {
            PlaylistScheduleAlarm.PHASE_PREWARM -> handlePrewarm(app, deltaMs)
            PlaylistScheduleAlarm.PHASE_POSTCHECK -> handlePostcheck(app, targetMs, deltaMs)
            else -> handleExact(app, deltaMs)
        }
    }

    private fun handlePrewarm(app: Context, deltaMs: Long) {
        ForegroundWakePolicy.syncPresentationState(app, true)
        RecoveryScheduler.enqueueNow(app, "schedule_prewarm")
        startWakeForegroundService(app, "schedule_prewarm", forceUiWake = false)
        FleetTelemetry.log(app, "schedule_prewarm_fired", "deltaMs=$deltaMs")
    }

    private fun handleExact(app: Context, deltaMs: Long) {
        // Legacy contract: keep presentation sync + recovery enqueue + FGS start for backwards
        // compatibility with the prior single-phase behavior.
        ForegroundWakePolicy.syncPresentationState(app, true)
        RecoveryScheduler.enqueueNow(app, "schedule_exact_boundary")
        startWakeForegroundService(app, "schedule_exact_boundary", forceUiWake = true)
        // Schedule-boundary wake always overrides ForegroundWakeGuard relaxed-teacher gating.
        if (ForegroundWakeGuard.allowScheduleBoundaryWake(app)) {
            val ok = CommandRelay.wakeApp(app)
            FleetTelemetry.log(
                app,
                "schedule_exact_fired",
                "deltaMs=$deltaMs wakeOk=$ok",
            )
        } else {
            FleetTelemetry.log(app, "schedule_exact_fired", "deltaMs=$deltaMs wakeOk=skipped")
        }
    }

    private fun handlePostcheck(app: Context, targetMs: Long, deltaMs: Long) {
        val lastUi = WatchdogState.lastUiHeartbeatMs(app)
        // UI is considered fresh when it bumped within [target - 1.5s, target + grace + 2s].
        val freshSinceMs = if (targetMs > 0L) targetMs - 1_500L else 0L
        val uiFresh = lastUi >= freshSinceMs
        val action: String =
            if (uiFresh) {
                "ok"
            } else {
                ForegroundWakePolicy.syncPresentationState(app, true)
                RecoveryScheduler.enqueueNow(app, "schedule_postcheck_stale")
                // Soft wake first.
                val wakeOk = CommandRelay.wakeApp(app)
                if (wakeOk) {
                    "wake"
                } else if (RecoveryLoopGuard.shouldThrottleAggressiveRelaunch(
                        app,
                        POSTCHECK_PATH,
                    )
                ) {
                    // Hard activity relaunch suppressed: keep the schedule recovery chain alive
                    // via FGS ACTION_WAKE + WM enqueue + alarm fallback. ForegroundWakePolicy
                    // + enqueueNow above already ran, so schedule eval still progresses.
                    RecoveryLoopGuard.onAggressiveRelaunchSuppressed(
                        context = app,
                        path = POSTCHECK_PATH,
                        softDelayMs = RecoveryLoopGuard.SOFT_FALLBACK_DELAY_MS,
                        extraDetail = "uiFresh=false wakeOk=false",
                    )
                    startWakeForegroundService(app, "schedule_postcheck_loop_soft", forceUiWake = true)
                    try {
                        RecoveryScheduler.scheduleAlarmFallback(
                            app,
                            "restart_loop_soft:schedule_postcheck",
                            RecoveryLoopGuard.SOFT_FALLBACK_DELAY_MS,
                        )
                    } catch (_: Throwable) {
                        // Soft path best-effort; staggered fallbacks remain armed elsewhere.
                    }
                    "loop_soft"
                } else {
                    val restartOk = restartApplication(app)
                    if (restartOk) "restart" else "restart_failed"
                }
            }
        FleetTelemetry.log(
            app,
            "schedule_postcheck_fired",
            "deltaMs=$deltaMs uiFresh=$uiFresh lastUiMs=$lastUi action=$action",
        )
    }

    private fun startWakeForegroundService(app: Context, source: String, forceUiWake: Boolean) {
        try {
            val svc = Intent(app, KioskForegroundService::class.java).apply {
                action = KioskForegroundService.ACTION_WAKE
                putExtra(BootReceiver.EXTRA_START_SOURCE, source)
                putExtra(RecoveryWakeRouter.EXTRA_FORCE_UI_WAKE, forceUiWake)
            }
            ContextCompat.startForegroundService(app, svc)
        } catch (t: Throwable) {
            Log.w(
                TAG,
                "event=schedule_boundary_fgs_failed source=ScheduleBoundaryAlarmReceiver " +
                    "wakeSource=$source msg=${t::class.java.simpleName}:${t.message}",
            )
            FleetTelemetry.log(
                app,
                "schedule_boundary_fgs_failed",
                "wakeSource=$source ${t::class.java.simpleName}",
            )
        }
    }

    /** Same launcher-intent relaunch as [MainActivity.restartApp]; usable from a receiver context. */
    private fun restartApplication(app: Context): Boolean = try {
        val launch = app.packageManager.getLaunchIntentForPackage(app.packageName)
            ?: Intent(app, MainActivity::class.java)
        launch.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TASK,
        )
        app.startActivity(launch)
        true
    } catch (t: Throwable) {
        Log.w(
            TAG,
            "event=schedule_postcheck_restart_failed msg=${t::class.java.simpleName}:${t.message}",
        )
        false
    }

    companion object {
        private const val TAG = "VertiSignageBG"

        /** Path label used by [RecoveryLoopGuard] for the schedule postcheck relaunch. */
        private const val POSTCHECK_PATH = "schedule_postcheck"
    }
}
