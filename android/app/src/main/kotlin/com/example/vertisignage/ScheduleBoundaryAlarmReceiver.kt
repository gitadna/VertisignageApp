package com.example.vertisignage

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Fires at the next playlist schedule boundary when [PlaylistScheduleAlarm] could schedule an exact alarm.
 * Complements the in-process Dart [Timer] when Doze or OEM delays would otherwise skew boundaries.
 */
class ScheduleBoundaryAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val app = context.applicationContext
        FleetTelemetry.log(app, "schedule_exact_boundary_fired")
        ForegroundWakePolicy.syncPresentationState(app, true)
        RecoveryScheduler.enqueueNow(app, "schedule_exact_boundary")
        try {
            ContextCompat.startForegroundService(
                app,
                Intent(app, KioskForegroundService::class.java).apply {
                    putExtra(BootReceiver.EXTRA_START_SOURCE, "schedule_exact_boundary")
                },
            )
        } catch (t: Throwable) {
            Log.w(
                TAG,
                "event=schedule_boundary_fgs_failed source=ScheduleBoundaryAlarmReceiver msg=${t::class.java.simpleName}:${t.message}",
            )
            FleetTelemetry.log(app, "schedule_exact_boundary_fgs_failed", t::class.java.simpleName)
        }
    }

    companion object {
        private const val TAG = "VertiSignageBG"
    }
}
