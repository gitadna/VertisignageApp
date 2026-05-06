package com.example.vertisignage

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.ContextCompat

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (!ALLOWED_ACTIONS.contains(action)) return

        val storageContext =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) context.createDeviceProtectedStorageContext()
            else context
        val prefs = storageContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        // Receiver-level idempotency to avoid duplicate service starts during rapid boot broadcasts.
        val nowMs = System.currentTimeMillis()
        val lastHandledAt = prefs.getLong(KEY_LAST_BOOT_EVENT_AT_MS, 0L)
        if (nowMs - lastHandledAt in 0..RECEIVER_DEDUPE_WINDOW_MS) return
        prefs.edit().putLong(KEY_LAST_BOOT_EVENT_AT_MS, nowMs).apply()

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

        try {
            val serviceIntent = Intent(context, KioskForegroundService::class.java).apply {
                putExtra(EXTRA_START_SOURCE, START_SOURCE_BOOT)
                putExtra(EXTRA_BOOT_ACTION, action)
            }
            ContextCompat.startForegroundService(context, serviceIntent)
        } catch (_: Throwable) {
            // Fail safe: the system/OEM may block background/FGS start; recovery worker will act as fallback.
            prefs.edit()
                .putBoolean(KEY_PENDING_BOOT_RECOVERY, true)
                .putString(KEY_PENDING_BOOT_RECOVERY_REASON, "fgs_start_blocked:$action")
                .apply()
            RecoveryScheduler.enqueueNow(storageContext, "boot_fgs_start_blocked:$action")
        }
    }

    companion object {
        private const val PREFS_NAME = "vertisignage_bg"

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
