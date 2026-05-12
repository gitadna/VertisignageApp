package com.example.vertisignage

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Three-phase exact-alarm chain for the next playlist boundary:
 *   - prewarm  @ target - prewarmLeadMs    (warm process + FGS + activity before content swap)
 *   - exact    @ target                    (boundary itself, BAL-friendly wake)
 *   - postcheck@ target + postcheckGraceMs (verify UI actually woke; escalate if not)
 *
 * Requires [SCHEDULE_EXACT_ALARM] on Android 12+ unless the app is on the allowlist.
 */
object PlaylistScheduleAlarm {
    private const val TAG = "VertiSignageBG"
    private const val REQUEST_EXACT = 55821
    private const val REQUEST_PREWARM = 55822
    private const val REQUEST_POSTCHECK = 55823

    const val EXTRA_PHASE = "phase"
    const val EXTRA_TARGET_MS = "targetMs"
    const val PHASE_PREWARM = "prewarm"
    const val PHASE_EXACT = "exact"
    const val PHASE_POSTCHECK = "postcheck"

    const val DEFAULT_PREWARM_LEAD_MS = 10_000L
    const val DEFAULT_POSTCHECK_GRACE_MS = 3_000L

    private const val PREFS_NAME = "vertisignage_bg"
    private const val KEY_LAST_TARGET_MS = "schedule_last_target_ms"
    private const val KEY_LAST_ARMED_AT_MS = "schedule_last_armed_at_ms"

    fun canScheduleExactAlarms(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val am = context.getSystemService(AlarmManager::class.java) ?: return false
        return am.canScheduleExactAlarms()
    }

    fun lastScheduledTargetMs(context: Context): Long =
        storagePrefs(context).getLong(KEY_LAST_TARGET_MS, 0L)

    /**
     * @return true if the [PHASE_EXACT] alarm was scheduled. Prewarm/postcheck failures are logged
     *         but do not abort: the exact alarm alone preserves the legacy behavior.
     */
    fun schedule(
        context: Context,
        triggerAtEpochMs: Long,
        prewarmLeadMs: Long = DEFAULT_PREWARM_LEAD_MS,
        postcheckGraceMs: Long = DEFAULT_POSTCHECK_GRACE_MS,
    ): Boolean {
        val app = context.applicationContext
        val am = app.getSystemService(AlarmManager::class.java) ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
            // Permission revoked or never granted (Android 14+ default). Surface this as a
            // dedicated event so dashboards can flag fleets needing onboarding remediation;
            // overall schedule recovery still falls back to the in-process Dart timer.
            FleetTelemetry.log(
                app,
                "schedule_boundary_alarm_denied",
                "reason=cannot_schedule_exact api=${Build.VERSION.SDK_INT}",
            )
            return false
        }
        val now = System.currentTimeMillis()
        // Exact phase: stay slightly ahead of the in-process Dart timer if the caller raced us.
        val exactAt = maxOf(triggerAtEpochMs, now + 3_000L)
        val safeLead = prewarmLeadMs.coerceAtLeast(0L)
        val safeGrace = postcheckGraceMs.coerceAtLeast(0L)
        val prewarmAt = maxOf(now + 500L, exactAt - safeLead)
        val postcheckAt = exactAt + safeGrace

        // Rapid re-arm detection: if schedule() ran <1s ago we have a Dart-side burst (e.g.
        // playlist sync churn). cancel()/UPDATE_CURRENT below already make this safe; the
        // telemetry exists so soak tests can spot pathological re-arming loops.
        val prevArmedAt = storagePrefs(app).getLong(KEY_LAST_ARMED_AT_MS, 0L)
        val prevTargetMs = storagePrefs(app).getLong(KEY_LAST_TARGET_MS, 0L)
        val sinceLastArmMs = if (prevArmedAt > 0L) now - prevArmedAt else -1L
        if (sinceLastArmMs in 0..1_000L) {
            FleetTelemetry.log(
                app,
                "schedule_boundary_rearm_burst",
                "sinceLastArmMs=$sinceLastArmMs prevTargetMs=$prevTargetMs newTargetMs=$exactAt",
            )
        }

        cancel(app)
        storagePrefs(app).edit()
            .putLong(KEY_LAST_TARGET_MS, exactAt)
            .putLong(KEY_LAST_ARMED_AT_MS, now)
            .apply()

        val prewarmOk =
            if (safeLead > 0L && prewarmAt < exactAt - 250L) {
                armPhase(app, am, REQUEST_PREWARM, PHASE_PREWARM, prewarmAt, exactAt)
            } else {
                false
            }
        val exactOk = armPhase(app, am, REQUEST_EXACT, PHASE_EXACT, exactAt, exactAt)
        val postcheckOk =
            if (safeGrace > 0L) {
                armPhase(app, am, REQUEST_POSTCHECK, PHASE_POSTCHECK, postcheckAt, exactAt)
            } else {
                false
            }

        FleetTelemetry.log(
            app,
            "schedule_boundary_alarm_scheduled",
            "exactAt=$exactAt prewarmAt=$prewarmAt prewarmOk=$prewarmOk " +
                "postcheckAt=$postcheckAt postcheckOk=$postcheckOk leadMs=$safeLead graceMs=$safeGrace",
        )
        return exactOk
    }

    fun cancel(context: Context) {
        val app = context.applicationContext
        val am = app.getSystemService(AlarmManager::class.java) ?: return
        for (rc in intArrayOf(REQUEST_EXACT, REQUEST_PREWARM, REQUEST_POSTCHECK)) {
            try {
                val pi = pendingIntent(app, rc)
                am.cancel(pi)
            } catch (_: Throwable) {
                // ignore — best effort
            }
        }
    }

    private fun armPhase(
        app: Context,
        am: AlarmManager,
        requestCode: Int,
        phase: String,
        triggerAt: Long,
        targetMs: Long,
    ): Boolean {
        return try {
            val pi = pendingIntent(app, requestCode, phase, targetMs)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            } else {
                @Suppress("DEPRECATION")
                am.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            }
            true
        } catch (se: SecurityException) {
            // Android 12+ may revoke SCHEDULE_EXACT_ALARM at runtime — surface as a dedicated
            // event so the fleet dashboard distinguishes "denied" from "system error".
            Log.w(
                TAG,
                "event=schedule_boundary_alarm_security_denied phase=$phase msg=${se.message}",
            )
            FleetTelemetry.log(
                app,
                "schedule_boundary_alarm_denied",
                "phase=$phase reason=security_exception",
            )
            false
        } catch (t: Throwable) {
            Log.w(
                TAG,
                "event=schedule_boundary_alarm_failed phase=$phase msg=${t::class.java.simpleName}:${t.message}",
            )
            FleetTelemetry.log(
                app,
                "schedule_boundary_alarm_failed",
                "phase=$phase ${t::class.java.simpleName}",
            )
            false
        }
    }

    private fun pendingIntent(
        app: Context,
        requestCode: Int,
        phase: String? = null,
        targetMs: Long = 0L,
    ): PendingIntent {
        val intent = Intent(app, ScheduleBoundaryAlarmReceiver::class.java).apply {
            if (phase != null) {
                putExtra(EXTRA_PHASE, phase)
                putExtra(EXTRA_TARGET_MS, targetMs)
            }
        }
        return PendingIntent.getBroadcast(
            app,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun storagePrefs(context: Context) =
        storageContext(context.applicationContext)
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun storageContext(context: Context): Context =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
}
