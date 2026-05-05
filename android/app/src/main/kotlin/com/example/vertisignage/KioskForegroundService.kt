package com.example.vertisignage

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import androidx.core.app.NotificationCompat

class KioskForegroundService : Service() {
    private val relaunchHandler = Handler(Looper.getMainLooper())
    private var relaunchCheckRunnable: Runnable? = null

    override fun onCreate() {
        super.onCreate()
        createChannelIfNeeded()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
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
        return START_STICKY
    }

    override fun onBind(intent: Intent?) = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        relaunchApp("task_removed")
        // Reassert sticky foreground service for best-effort resilience when task is swiped away.
        ContextCompat.startForegroundService(
            this,
            Intent(this, KioskForegroundService::class.java),
        )
        scheduleRelaunchGuard()
    }

    override fun onDestroy() {
        relaunchCheckRunnable?.let { relaunchHandler.removeCallbacks(it) }
        relaunchCheckRunnable = null
        super.onDestroy()
    }

    private fun relaunchApp(reason: String) {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        launch.putExtra("kiosk_relaunch_reason", reason)
        startActivity(launch)
    }

    /**
     * When recents-swipe and LMK race, app relaunch can be dropped.
     * This one-shot delayed relaunch improves resilience without loops.
     */
    private fun scheduleRelaunchGuard() {
        relaunchCheckRunnable?.let { relaunchHandler.removeCallbacks(it) }
        relaunchCheckRunnable = Runnable {
            relaunchApp("task_removed_guard")
        }
        relaunchHandler.postDelayed(relaunchCheckRunnable!!, 2500L)
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val ch = NotificationChannel(
            CHANNEL_ID,
            "VertiSignage playback",
            NotificationManager.IMPORTANCE_LOW,
        )
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(ch)
    }

    private fun buildNotification(): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
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

    companion object {
        private const val NOTIFICATION_ID = 71001
        private const val CHANNEL_ID = "vertisignage_kiosk_fg"
    }
}
