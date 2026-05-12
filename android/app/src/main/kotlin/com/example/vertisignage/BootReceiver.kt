package com.example.vertisignage

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (!ALLOWED_ACTIONS.contains(action)) return
        if (isInitialStickyBroadcast) return
        if (action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            val replacedPackage = intent.data?.schemeSpecificPart
            if (!replacedPackage.isNullOrBlank() && replacedPackage != context.packageName) return
        }

        val storageContext =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) context.createDeviceProtectedStorageContext()
            else context
        val prefs = storageContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        // Receiver-level idempotency to avoid duplicate service starts during rapid boot broadcasts.
        val nowMs = System.currentTimeMillis()
        val lastHandledAt = prefs.getLong(KEY_LAST_BOOT_EVENT_AT_MS, 0L)
        if (nowMs - lastHandledAt in 0..RECEIVER_DEDUPE_WINDOW_MS) return
        prefs.edit().putLong(KEY_LAST_BOOT_EVENT_AT_MS, nowMs).apply()

        BootTiming.markBootReceived(storageContext)
        FleetTelemetry.log(storageContext, "boot_received", "action=$action")

        // Do not auto-start anything until the user has launched the app at least once after install.
        val firstLaunchCompleted = prefs.getBoolean(KEY_FIRST_LAUNCH_COMPLETED, false)
        if (!firstLaunchCompleted) {
            prefs.edit()
                .putBoolean(KEY_PENDING_BOOT_RECOVERY, true)
                .putString(KEY_PENDING_BOOT_RECOVERY_REASON, action)
                .apply()
            RecoveryScheduler.enqueueNow(storageContext, "boot_pending_first_launch:$action")
            return
        }

        RecoveryScheduler.ensurePeriodic(storageContext, "boot:$action")
        RecoveryScheduler.enqueueNow(storageContext, "boot:$action")
        // Layered fallback chain for OEMs that throttle boot work: each window arms an
        // independent RecoveryAlarmReceiver pending so a single missed wake cannot strand the app.
        RecoveryScheduler.scheduleBootStaggeredFallbacks(storageContext, "boot:$action")

        try {
            // Single FGS start that both pins the service AND routes a BAL-safe activity wake on
            // Android 12+. We deliberately do NOT call CommandRelay.wakeApp directly from a boot
            // receiver context anymore — the system blocks receiver-driven startActivity on most
            // post-S devices, so the FGS ACTION_WAKE path inside KioskForegroundService.onStartCommand
            // is now the canonical wake-up route.
            val bootAction = action
            val attemptId = RecoveryAnalyticsEmitter.newAttemptId()
            val serviceIntent = Intent(context, KioskForegroundService::class.java).apply {
                this.action = KioskForegroundService.ACTION_WAKE
                putExtra(EXTRA_START_SOURCE, START_SOURCE_BOOT)
                putExtra(EXTRA_BOOT_ACTION, bootAction)
                putExtra(RecoveryAnalyticsEmitter.EXTRA_RECOVERY_ATTEMPT_ID, attemptId)
            }
            ContextCompat.startForegroundService(context, serviceIntent)
            BootTiming.markBootFgsStarted(storageContext)
            FleetTelemetry.log(storageContext, "boot_fgs_started", "action=$action")
        } catch (t: Throwable) {
            // Fail safe: the system/OEM may block background/FGS start; staggered alarms still cover us.
            Log.w(TAG, "event=boot_fgs_start_blocked source=BootReceiver action=$action msg=${t::class.java.simpleName}:${t.message}")
            prefs.edit()
                .putBoolean(KEY_PENDING_BOOT_RECOVERY, true)
                .putString(KEY_PENDING_BOOT_RECOVERY_REASON, "fgs_start_blocked:$action")
                .apply()
            RecoveryScheduler.enqueueNow(storageContext, "boot_fgs_start_blocked:$action")
            RecoveryScheduler.scheduleAlarmFallback(storageContext, "boot_fgs_start_blocked:$action", 10_000L)
        }
    }

    companion object {
        private const val PREFS_NAME = "vertisignage_bg"
        private const val TAG = "VertiSignageBG"

        // Written by Flutter (via MainActivity bridge) only after first successful app launch.
        const val KEY_FIRST_LAUNCH_COMPLETED = "first_launch_completed"

        // Used when reboot/package-replaced happens before first launch or start is blocked.
        const val KEY_PENDING_BOOT_RECOVERY = "pending_boot_recovery"
        const val KEY_PENDING_BOOT_RECOVERY_REASON = "pending_boot_recovery_reason"

        // Receiver-level dedupe window.
        private const val KEY_LAST_BOOT_EVENT_AT_MS = "last_boot_event_at_ms"
        private const val RECEIVER_DEDUPE_WINDOW_MS = 10_000L

        // Extras passed to the foreground service.
        const val EXTRA_START_SOURCE = "extra_start_source"
        const val EXTRA_BOOT_ACTION = "extra_boot_action"
        const val START_SOURCE_BOOT = "boot"

        private val ALLOWED_ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
        )
    }
}
