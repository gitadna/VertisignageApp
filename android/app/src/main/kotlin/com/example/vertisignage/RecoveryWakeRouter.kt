package com.example.vertisignage

import android.content.Context
import android.os.Build

/**
 * Single authority for whether recovery should call [CommandRelay.wakeApp] (activity to foreground).
 * FGS / WorkManager / alarms are started separately by callers.
 */
object RecoveryWakeRouter {
    const val EXTRA_FORCE_UI_WAKE = "extra_force_ui_wake"

    /**
     * @param forceUiWakeIntent schedule/push paths set this true so boundary wakes stay reliable.
     * @param forceWakeUiFromWorker [RecoveryWorker.EXTRA_FORCE_WAKE_UI] when service/UI heartbeats stale.
     * @param startSource [BootReceiver.EXTRA_START_SOURCE] e.g. boot, alarm, schedule_*, workmanager.
     */
    fun shouldBringActivityToForeground(
        context: Context,
        forceUiWakeIntent: Boolean,
        forceWakeUiFromWorker: Boolean,
        startSource: String?,
    ): Boolean {
        val app = context.applicationContext
        if (forceUiWakeIntent) return true
        if (ForegroundWakePolicy.presentationWantsForeground(app)) return true
        if (WatchdogState.presentationRequiresVisibility(app)) return true
        if (isBootLikeStart(startSource) && needsBootUiWake(app)) return true
        if (forceWakeUiFromWorker && ForegroundWakeGuard.allowRecoveryBringToForeground(app)) {
            return ForegroundWakePolicy.presentationWantsForeground(app) ||
                WatchdogState.presentationRequiresVisibility(app)
        }
        return false
    }

    private fun isBootLikeStart(startSource: String?): Boolean =
        startSource == BootReceiver.START_SOURCE_BOOT

    private fun needsBootUiWake(app: Context): Boolean {
        if (VertiSignageApp.cachedEngine() == null) return true
        val sc =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                app.createDeviceProtectedStorageContext()
            } else {
                app
            }
        return try {
            val p = sc.getSharedPreferences("vertisignage_bg", Context.MODE_PRIVATE)
            p.getBoolean(BootReceiver.KEY_PENDING_BOOT_RECOVERY, false)
        } catch (_: Throwable) {
            false
        }
    }
}
