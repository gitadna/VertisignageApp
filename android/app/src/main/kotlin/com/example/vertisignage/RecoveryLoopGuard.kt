package com.example.vertisignage

import android.content.Context
import android.os.Build

/**
 * Crash-loop / recovery-loop dampener.
 *
 * Records process-start timestamps in a small ring buffer in device-protected storage.
 * Recovery and FGS callers can ask [inLoop] / [shouldThrottleAggressiveRelaunch] to throttle
 * aggressive activity-relaunch escalation paths (restartApp, schedule postcheck restart,
 * crash-handler activity alarm) when the device is clearly stuck in a restart cycle.
 *
 * Hard rule: this object is allowed to dampen ONLY full-task activity relaunches. Foreground
 * service, WorkManager recovery, alarms, ACTION_WAKE, websocket, overlays, schedule evaluation
 * and playback must continue regardless of loop state. The decision-making and any soft
 * fallback wiring remain in the call sites; this object is a tiny shared signal + telemetry
 * helper.
 */
object RecoveryLoopGuard {
    private const val PREFS_NAME = "vertisignage_bg"
    private const val KEY_RING = "recovery_loop_ring"
    private const val KEY_LAST_IN_LOOP = "recovery_loop_last_in_loop"
    private const val RING_SIZE = 8
    /** Default window for [inLoop]: 4 process starts within 90s flags the device as looping. */
    const val DEFAULT_WINDOW_MS = 90_000L
    const val DEFAULT_THRESHOLD = 4

    /** Soft escalation delay applied when an aggressive relaunch is suppressed. */
    const val SOFT_FALLBACK_DELAY_MS = 15_000L

    /** Append the current wall-clock time to the ring buffer. Best effort. */
    fun recordProcessStart(context: Context) {
        try {
            val now = System.currentTimeMillis()
            val ring = read(context).toMutableList()
            ring.add(now)
            while (ring.size > RING_SIZE) ring.removeAt(0)
            write(context, ring)
        } catch (_: Throwable) {
            // Diagnostics must never break boot path.
        }
    }

    /** True when at least [threshold] starts have happened within [windowMs] of now. */
    fun inLoop(
        context: Context,
        windowMs: Long = DEFAULT_WINDOW_MS,
        threshold: Int = DEFAULT_THRESHOLD,
    ): Boolean {
        return try {
            val now = System.currentTimeMillis()
            val cutoff = now - windowMs
            val recent = read(context).count { it >= cutoff }
            recent >= threshold
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Readable alias for call sites that gate aggressive activity relaunches. Logs
     * `recovery_loop_detected` exactly once per **path** per loop episode (sticky) — repeat
     * suppressions inside the same window emit only `recovery_restart_suppressed` /
     * `recovery_restart_delayed` and skip the redundant detection event.
     *
     * Returns the current loop state.
     */
    fun shouldThrottleAggressiveRelaunch(context: Context, path: String): Boolean {
        val nowLoop = inLoop(context)
        updateLoopTransition(context, nowLoop, path)
        return nowLoop
    }

    /**
     * Centralized telemetry for a suppressed aggressive relaunch. Emits
     * `recovery_restart_suppressed` and (when [softDelayMs] > 0) `recovery_restart_delayed`
     * so dashboards can distinguish "fully skipped" from "deferred to soft path".
     *
     * Call sites must still wire the soft fallback (`RecoveryScheduler.enqueueNow` +
     * `scheduleAlarmFallback` and/or FGS `ACTION_WAKE`); this helper only logs.
     */
    fun onAggressiveRelaunchSuppressed(
        context: Context,
        path: String,
        softDelayMs: Long = 0L,
        extraDetail: String? = null,
    ) {
        val recent = recentCount(context)
        val windowRemainingMs = windowRemainingMs(context)
        val detail = buildString {
            append("path=").append(path)
            append(" recent=").append(recent)
            append(" windowRemainingMs=").append(windowRemainingMs)
            if (!extraDetail.isNullOrBlank()) {
                append(' ').append(extraDetail)
            }
        }
        safeTelemetry(context, "recovery_restart_suppressed", detail)
        if (softDelayMs > 0L) {
            safeTelemetry(
                context,
                "recovery_restart_delayed",
                "path=$path delayMs=$softDelayMs",
            )
        }
    }

    /** Most recent process start timestamps, ascending. */
    fun snapshot(context: Context): List<Long> = read(context)

    /** Number of starts inside the default window. Best effort, never throws. */
    fun recentCount(
        context: Context,
        windowMs: Long = DEFAULT_WINDOW_MS,
    ): Int = try {
        val cutoff = System.currentTimeMillis() - windowMs
        read(context).count { it >= cutoff }
    } catch (_: Throwable) {
        0
    }

    /**
     * Milliseconds until the oldest in-window start ages out — i.e. how long the loop window
     * has left before naturally clearing if no further restarts happen. Returns 0 when not in
     * a loop or when prefs read fails.
     */
    fun windowRemainingMs(
        context: Context,
        windowMs: Long = DEFAULT_WINDOW_MS,
    ): Long = try {
        val now = System.currentTimeMillis()
        val cutoff = now - windowMs
        val recent = read(context).filter { it >= cutoff }
        if (recent.isEmpty()) 0L else (recent.first() + windowMs - now).coerceAtLeast(0L)
    } catch (_: Throwable) {
        0L
    }

    /**
     * Records the current loop state and emits exactly one transition event when the device
     * leaves a loop (`recovery_loop_cleared`) or enters one (`recovery_loop_detected`).
     */
    private fun updateLoopTransition(context: Context, nowLoop: Boolean, path: String) {
        try {
            val prefs = prefs(context)
            val wasLoop = prefs.getBoolean(KEY_LAST_IN_LOOP, false)
            if (nowLoop && !wasLoop) {
                prefs.edit().putBoolean(KEY_LAST_IN_LOOP, true).apply()
                safeTelemetry(
                    context,
                    "recovery_loop_detected",
                    "path=$path recent=${recentCount(context)} " +
                        "windowRemainingMs=${windowRemainingMs(context)}",
                )
            } else if (!nowLoop && wasLoop) {
                prefs.edit().putBoolean(KEY_LAST_IN_LOOP, false).apply()
                safeTelemetry(
                    context,
                    "recovery_loop_cleared",
                    "path=$path recent=${recentCount(context)}",
                )
            }
        } catch (_: Throwable) {
            // Telemetry must never crash recovery.
        }
    }

    private fun safeTelemetry(context: Context, event: String, detail: String) {
        try {
            FleetTelemetry.log(context, event, detail)
        } catch (_: Throwable) {
            // ignore — diagnostics only
        }
    }

    private fun read(context: Context): List<Long> {
        val raw = prefs(context).getString(KEY_RING, null) ?: return emptyList()
        if (raw.isEmpty()) return emptyList()
        return raw.split(',').mapNotNull { it.trim().toLongOrNull() }
    }

    private fun write(context: Context, ring: List<Long>) {
        prefs(context).edit()
            .putString(KEY_RING, ring.joinToString(","))
            .apply()
    }

    private fun prefs(context: Context) = storageContext(context.applicationContext)
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun storageContext(context: Context): Context =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
}
