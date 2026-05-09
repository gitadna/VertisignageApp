package com.example.vertisignage

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

class KioskForegroundService : Service() {
    private var foregroundStarted = false
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createChannelIfNeeded()
        RecoveryScheduler.ensurePeriodic(applicationContext, "service_create")
        log(
            event = "service_create",
            action = null,
            reason = null,
        )
        WatchdogState.markServiceHeartbeat(applicationContext)
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        val startSource = intent?.getStringExtra(BootReceiver.EXTRA_START_SOURCE)
        val bootAction = intent?.getStringExtra(BootReceiver.EXTRA_BOOT_ACTION)
        val forceWakeUi = intent?.getBooleanExtra(RecoveryWorker.EXTRA_FORCE_WAKE_UI, false) == true
        WatchdogState.markServiceHeartbeat(applicationContext)
        acquireWakeLock()

        log(
            event = "service_start_command",
            action = action,
            reason = listOfNotNull(
                startSource?.let { "source=$it" },
                bootAction?.let { "bootAction=$it" },
                "flags=$flags",
                "startId=$startId",
            ).joinToString(","),
        )

        RecoveryScheduler.enqueueNow(applicationContext, "service_start_command:${action ?: "null"}")
        RecoveryScheduler.scheduleAlarmFallback(applicationContext, "service_start", 120_000L)

        // Idempotent foreground promotion: multiple startService/startForegroundService calls can race at boot.
        if (!foregroundStarted) {
            try {
                val notification = buildNotification()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    startForeground(NOTIFICATION_ID, notification)
                }
                foregroundStarted = true
            } catch (t: Throwable) {
                // Fail safe: if OEM/system blocks FGS or notification posting fails, don't crash-loop.
                log(
                    event = "service_start_foreground_failed",
                    action = action,
                    reason = "${t::class.java.simpleName}:${t.message}",
                    level = Log.WARN,
                )
                RecoveryScheduler.enqueueNow(applicationContext, "service_start_foreground_failed:${t::class.java.simpleName}")
                stopSelf()
                return START_NOT_STICKY
            }
        }

        if (action == ACTION_WAKE) {
            val nowMs = System.currentTimeMillis()
            val shouldWake =
                synchronized(LOCK) {
                    if (nowMs - lastWakeAtMs in 0..WAKE_DEDUPE_WINDOW_MS) {
                        false
                    } else {
                        lastWakeAtMs = nowMs
                        true
                    }
                }

            if (shouldWake) {
                val ok = CommandRelay.wakeApp(this)
                if (!ok) {
                    RecoveryScheduler.enqueueNow(applicationContext, "wake_failed:$action")
                    RecoveryScheduler.scheduleAlarmFallback(applicationContext, "wake_failed:$action", 15_000L)
                }
                log(
                    event = "wake_app",
                    action = action,
                    reason = if (ok) "ok" else "failed",
                )
            } else {
                log(
                    event = "wake_app_skipped",
                    action = action,
                    reason = "deduped",
                )
            }
        }
        if (forceWakeUi) {
            if (ForegroundWakeGuard.allowRecoveryBringToForeground(this)) {
                val ok = CommandRelay.wakeApp(this)
                if (!ok) {
                    RecoveryScheduler.enqueueNow(applicationContext, "force_wake_failed")
                    RecoveryScheduler.scheduleAlarmFallback(applicationContext, "force_wake_failed", 15_000L)
                }
            } else {
                log(event = "force_wake_ui_skipped", action = action, reason = "foreground_wake_guard")
            }
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        log(event = "service_task_removed", action = null, reason = null, level = Log.WARN)
        RecoveryScheduler.enqueueNow(applicationContext, "service_task_removed")
        val ok =
            if (ForegroundWakeGuard.allowRecoveryBringToForeground(this)) {
                CommandRelay.wakeApp(this)
            } else {
                log(event = "task_removed_wake_skipped", action = null, reason = "foreground_wake_guard", level = Log.INFO)
                false
            }
        if (!ok) {
            RecoveryScheduler.scheduleAlarmFallback(applicationContext, "task_removed_wake_failed", 10_000L)
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?) = null

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val ch = NotificationChannel(
            CHANNEL_ID,
            "VertiSignage playback",
            NotificationManager.IMPORTANCE_LOW,
        )
        val nm = getSystemService(NotificationManager::class.java)
        try {
            nm?.createNotificationChannel(ch)
        } catch (t: Throwable) {
            log(
                event = "notification_channel_create_failed",
                action = null,
                reason = "${t::class.java.simpleName}:${t.message}",
                level = Log.WARN,
            )
        }
    }

    private fun buildNotification(): Notification {
        val launch =
            packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("VertiSignage")
            .setContentText("Display active")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(PowerManager::class.java) ?: return
            val lock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:KioskFg")
            lock.setReferenceCounted(false)
            lock.acquire(WAKELOCK_TIMEOUT_MS)
            wakeLock = lock
        } catch (_: Throwable) {
            // Best effort: no wake lock should never crash the service.
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Throwable) {
            // ignore
        } finally {
            wakeLock = null
        }
    }

    private fun log(
        event: String,
        action: String?,
        reason: String?,
        level: Int = Log.INFO,
    ) {
        val msg =
            buildString {
                append("event=").append(event)
                append(" source=KioskForegroundService")
                append(" action=").append(action ?: "null")
                append(" api=").append(Build.VERSION.SDK_INT)
                append(" manufacturer=").append(Build.MANUFACTURER ?: "unknown")
                append(" reason=").append(reason ?: "null")
            }
        when (level) {
            Log.WARN -> Log.w(TAG, msg)
            Log.ERROR -> Log.e(TAG, msg)
            else -> Log.i(TAG, msg)
        }
    }

    companion object {
        /** Starts MainActivity from foreground-service context (BAL-friendly). */
        const val ACTION_WAKE = "com.example.vertisignage.KioskForegroundService.ACTION_WAKE"

        private const val NOTIFICATION_ID = 71001
        private const val CHANNEL_ID = "vertisignage_kiosk_fg"

        private const val TAG = "VertiSignageBG"
        private val LOCK = Any()
        private var lastWakeAtMs: Long = 0L
        private const val WAKE_DEDUPE_WINDOW_MS = 3_000L
        private const val WAKELOCK_TIMEOUT_MS = 10 * 60_000L
    }
}
