package com.example.vertisignage

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Central Module 4 recovery authority: adaptive watchdog scheduling + staged foreground/surface recovery.
 * Best-effort only; must never throw.
 */
object PresentationRecoveryCoordinator {
    private const val TAG = "VertiSignageBG"
    private const val PREFS_BG = "vertisignage_bg"
    private const val KEY_M4_NEXT_STAGE = "m4_next_escalation_stage"
    private const val OWNER = "watchdog_m4"
    private var inFlightUntilMs: Long = 0L

    fun onWatchdogTick(context: Context, source: String) {
        try {
            val app = context.applicationContext
            FleetTelemetry.log(app, "m4_watchdog_tick", "source=$source")
            WatchdogState.markM4WatchdogTick(app)

            if (!WatchdogState.m4WatchdogEnabled(app)) {
                ActiveWatchdogAlarmReceiver.disarm(app)
                return
            }

            if (!isFirstLaunchComplete(app)) {
                ActiveWatchdogAlarmReceiver.arm(app, 120_000L)
                return
            }

            val profile =
                if (WatchdogState.m4OemProfileEnabled(app)) {
                    OemRecoveryProfile.current()
                } else {
                    OemRecoveryProfile.current().copy(id = "oem_off")
                }

            val wantsFg = ForegroundWakePolicy.presentationWantsForeground(app)
            val requiresVis = WatchdogState.presentationRequiresVisibility(app)
            val presenting = wantsFg || requiresVis

            if (!presenting) {
                bgPrefs(app).edit().putInt(KEY_M4_NEXT_STAGE, 1).apply()
                ActiveWatchdogAlarmReceiver.arm(app, profile.healthyIntervalMs)
                return
            }

            val now = System.currentTimeMillis()
            val flutterRt = WatchdogState.lastFlutterRuntimeHeartbeatMs(app)
            val flutterAge = if (flutterRt <= 0L) Long.MAX_VALUE else now - flutterRt
            val nativeUi = WatchdogState.lastUiHeartbeatMs(app)
            val nativeUiAge = if (nativeUi <= 0L) Long.MAX_VALUE else now - nativeUi
            val playerFrame = WatchdogState.lastFlutterPlayerFrameMs(app)
            val playerFrameAge = if (playerFrame <= 0L) Long.MAX_VALUE else now - playerFrame
            val playbackState = WatchdogState.flutterPlaybackState(app).lowercase()
            val playingLike =
                playbackState.contains("play") ||
                    playbackState == "active" ||
                    playbackState == "running"

            val flutterStale = flutterAge > profile.flutterStalePresentingMs
            val nativeStale = nativeUiAge > profile.nativeUiStaleMs
            val playerStale =
                playingLike && playerFrameAge > profile.playerFrameStaleMs &&
                    flutterAge < profile.flutterStalePresentingMs

            val freezeMode =
                WatchdogState.m4SurfaceRecoveryEnabled(app) && playerStale && !flutterStale

            val needRecover = flutterStale || nativeStale || freezeMode

            if (!needRecover) {
                bgPrefs(app).edit().putInt(KEY_M4_NEXT_STAGE, 1).apply()
                ActiveWatchdogAlarmReceiver.arm(
                    app,
                    if (presenting) profile.presentingIntervalMs else profile.healthyIntervalMs,
                )
                return
            }

            if (now < inFlightUntilMs) {
                FleetTelemetry.log(app, "m4_recovery_suppressed_inflight", "untilMs=$inFlightUntilMs")
                ActiveWatchdogAlarmReceiver.arm(app, profile.presentingIntervalMs)
                return
            }
            inFlightUntilMs = now + 12_000L

            if (WatchdogState.m4VisibilityEnforcementEnabled(app) &&
                (requiresVis || wantsFg) &&
                !ForegroundWakeGuard.allowRecoveryBringToForeground(app)
            ) {
                ForegroundWakePolicy.syncPresentationState(app, true)
                FleetTelemetry.log(app, "m4_recovery_hint", "watchdog_m4_visibility")
            }

            val windowId = "w_${now}_$source"
            if (!ForegroundOwnershipState.tryBeginRecoveryWindow(app, windowId, 8_000L)) {
                FleetTelemetry.log(app, "m4_recovery_suppressed_window", "id=$windowId")
                inFlightUntilMs = 0L
                ActiveWatchdogAlarmReceiver.arm(app, profile.presentingIntervalMs)
                return
            }

            if (!ForegroundOwnershipState.tryAcquireOwner(
                    app,
                    OWNER,
                    source,
                    ttlMs = 45_000L,
                    priority = ForegroundOwnershipState.PRIORITY_WATCHDOG,
                )
            ) {
                FleetTelemetry.log(app, "m4_recovery_suppressed_owner", "detail=$source")
                ForegroundOwnershipState.endRecoveryWindow(app)
                inFlightUntilMs = 0L
                ActiveWatchdogAlarmReceiver.arm(app, profile.presentingIntervalMs)
                return
            }

            FleetTelemetry.log(
                app,
                "m4_recovery_begin",
                "reason=$source flutterStale=$flutterStale nativeStale=$nativeStale freezeMode=$freezeMode",
            )

            val prefs = bgPrefs(app)
            val stage =
                if (freezeMode) {
                    3
                } else {
                    prefs.getInt(KEY_M4_NEXT_STAGE, 1).coerceIn(1, 5)
                }

            var executed = false
            if (freezeMode && !stageCooldownOk(app, 3, profile, now)) {
                FleetTelemetry.log(app, "m4_recovery_suppressed_cooldown", "stage=3_freeze")
            } else {
                var s = stage
                while (s <= 5 && !executed) {
                    if (stageCooldownOk(app, s, profile, now)) {
                        executed = executeStage(app, s, source, profile)
                        if (executed) {
                            WatchdogState.markStageExecuted(app, s)
                            WatchdogState.recordM4RecoveryStage(app, s, source)
                        }
                        break
                    } else {
                        FleetTelemetry.log(app, "m4_recovery_suppressed_cooldown", "stage=$s")
                        if (freezeMode) break
                        s++
                    }
                }
            }

            if (executed) {
                val next =
                    if (freezeMode) {
                        1
                    } else {
                        (stage.coerceAtMost(5) + 1).coerceAtMost(5)
                    }
                prefs.edit().putInt(KEY_M4_NEXT_STAGE, next).apply()
            }

            ForegroundOwnershipState.releaseOwnerIfMatches(app, OWNER)
            ForegroundOwnershipState.endRecoveryWindow(app)
            inFlightUntilMs = 0L

            val nextDelay =
                if (freezeMode) {
                    profile.urgentIntervalMs
                } else {
                    profile.presentingIntervalMs
                }
            ActiveWatchdogAlarmReceiver.arm(app, nextDelay)
            FleetTelemetry.log(app, "m4_recovery_result", "executed=$executed nextStage=${prefs.getInt(KEY_M4_NEXT_STAGE, 1)}")
        } catch (t: Throwable) {
            Log.w(TAG, "event=m4_watchdog_tick_failed msg=${t::class.java.simpleName}:${t.message}")
            try {
                ActiveWatchdogAlarmReceiver.arm(context.applicationContext, 120_000L)
            } catch (_: Throwable) {
            }
        }
    }

    /** External hooks (task removed, screen on, trim memory). */
    fun notifyTrigger(context: Context, reason: String) {
        try {
            val app = context.applicationContext
            if (!WatchdogState.m4WatchdogEnabled(app)) return
            FleetTelemetry.log(app, "m4_external_trigger", reason)
            ForegroundOwnershipState.endRecoveryWindow(app)
            bgPrefs(app).edit().putInt(KEY_M4_NEXT_STAGE, 1).apply()
            onWatchdogTick(app, "external:$reason")
        } catch (_: Throwable) {
        }
    }

    fun ensureWatchdogArmed(context: Context) {
        try {
            if (!WatchdogState.m4WatchdogEnabled(context.applicationContext)) return
            val profile = OemRecoveryProfile.current()
            ActiveWatchdogAlarmReceiver.arm(context.applicationContext, profile.healthyIntervalMs)
        } catch (_: Throwable) {
        }
    }

    private fun stageCooldownOk(
        app: Context,
        stage: Int,
        profile: OemRecoveryProfile,
        now: Long,
    ): Boolean {
        val last = WatchdogState.lastStageCooldownMs(app, stage)
        if (last <= 0L) return true
        val need =
            when (stage) {
                1 -> profile.stage1CooldownMs
                2 -> profile.stage2CooldownMs
                3 -> profile.stage3CooldownMs
                4 -> profile.stage4CooldownMs
                else -> 30_000L
            }
        return now - last >= need
    }

    private fun executeStage(
        app: Context,
        stage: Int,
        source: String,
        profile: OemRecoveryProfile,
    ): Boolean {
        return when (stage) {
            1 -> {
                try {
                    ContextCompat.startForegroundService(
                        app,
                        Intent(app, KioskForegroundService::class.java).apply {
                            action = KioskForegroundService.ACTION_WAKE
                            putExtra(BootReceiver.EXTRA_START_SOURCE, "watchdog_m4")
                            putExtra(RecoveryWorker.EXTRA_RECOVERY_REASON, "watchdog_m4:$source")
                        },
                    )
                    WatchdogState.markForegroundRestore(app)
                    FleetTelemetry.log(app, "m4_recovery_stage", "stage=1")
                    true
                } catch (t: Throwable) {
                    FleetTelemetry.log(app, "m4_recovery_stage_failed", "stage=1 ${t::class.java.simpleName}")
                    false
                }
            }
            2 -> {
                if (!ForegroundWakeGuard.allowRecoveryBringToForeground(app)) {
                    FleetTelemetry.log(app, "m4_recovery_stage_skipped_guard", "stage=2")
                    return false
                }
                if (!RecoveryWakeRouter.shouldBringActivityToForeground(
                        app,
                        forceUiWakeIntent = false,
                        forceWakeUiFromWorker = false,
                        startSource = "watchdog_m4",
                    )
                ) {
                    FleetTelemetry.log(app, "m4_recovery_stage_skipped_router", "stage=2")
                    return false
                }
                val ok = CommandRelay.wakeApp(app)
                WatchdogState.markForegroundRestore(app)
                FleetTelemetry.log(app, "m4_recovery_stage", "stage=2 ok=$ok")
                ok
            }
            3 -> {
                if (!WatchdogState.m4SurfaceRecoveryEnabled(app)) return false
                WatchdogState.incrementM4SurfaceRecoveries(app)
                NativeToFlutterRecovery.postRecoverPresentationSurface(app)
                FleetTelemetry.log(app, "m4_recovery_stage", "stage=3_surface")
                true
            }
            4 -> {
                if (!ForegroundWakeGuard.allowRecoveryBringToForeground(app)) {
                    FleetTelemetry.log(app, "m4_recovery_stage_skipped_guard", "stage=4")
                    return false
                }
                if (!RecoveryWakeRouter.shouldBringActivityToForeground(
                        app,
                        forceUiWakeIntent = false,
                        forceWakeUiFromWorker = false,
                        startSource = "watchdog_m4",
                    )
                ) {
                    FleetTelemetry.log(app, "m4_recovery_stage_skipped_router", "stage=4")
                    return false
                }
                if (RecoveryLoopGuard.shouldThrottleAggressiveRelaunch(app, "watchdog_m4_stage4")) {
                    RecoveryLoopGuard.onAggressiveRelaunchSuppressed(
                        app,
                        "watchdog_m4_stage4",
                        RecoveryLoopGuard.SOFT_FALLBACK_DELAY_MS,
                    )
                    RecoveryScheduler.enqueueNow(app, "watchdog_m4_stage4_suppressed")
                    RecoveryScheduler.scheduleAlarmFallback(
                        app,
                        "watchdog_m4_stage4_suppressed",
                        RecoveryLoopGuard.SOFT_FALLBACK_DELAY_MS,
                    )
                    return false
                }
                val ok = controlledRelaunch(app)
                FleetTelemetry.log(app, "m4_recovery_stage", "stage=4 ok=$ok")
                ok
            }
            5 -> {
                RecoveryScheduler.enqueueNow(app, "watchdog_m4_escalation:$source")
                RecoveryScheduler.scheduleAlarmFallback(app, "watchdog_m4_stage5", 60_000L)
                FleetTelemetry.log(app, "m4_recovery_stage", "stage=5_passive")
                true
            }
            else -> false
        }
    }

    private fun controlledRelaunch(app: Context): Boolean {
        return try {
            val launch = app.packageManager.getLaunchIntentForPackage(app.packageName)
                ?: Intent(app, MainActivity::class.java)
            launch.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK,
            )
            app.startActivity(launch)
            WatchdogState.incrementM4RelaunchCount(app)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun isFirstLaunchComplete(ctx: Context): Boolean {
        return try {
            bgPrefs(ctx).getBoolean(BootReceiver.KEY_FIRST_LAUNCH_COMPLETED, false)
        } catch (_: Throwable) {
            false
        }
    }

    private fun bgPrefs(ctx: Context): android.content.SharedPreferences {
        val sc =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                ctx.createDeviceProtectedStorageContext()
            } else {
                ctx
            }
        return sc.getSharedPreferences(PREFS_BG, Context.MODE_PRIVATE)
    }
}
