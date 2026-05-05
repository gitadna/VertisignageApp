package com.example.vertisignage

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.PowerManager

object CommandRelay {
    const val ACTION_WAKE = "com.example.vertisignage.ACTION_WAKE"
    const val ACTION_OVERLAY_SHOW = "com.example.vertisignage.ACTION_OVERLAY_SHOW"
    const val ACTION_OVERLAY_HIDE = "com.example.vertisignage.ACTION_OVERLAY_HIDE"

    const val EXTRA_TEXT = "text"
    const val EXTRA_MEDIA_URL = "mediaUrl"
    const val EXTRA_MEDIA_KIND = "mediaKind"
    const val EXTRA_UNTIL_DISMISSED = "untilDismissed"
    const val EXTRA_DURATION_SEC = "durationSec"
    const val EXTRA_OPACITY = "opacity"

    fun wakeApp(context: Context, activity: Activity? = null) {
        wakeScreen(context)
        dismissKeyguard(context, activity)
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        launch.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
        )
        context.startActivity(launch)
    }

    fun hideOverlay(context: Context) {
        val intent = Intent(context, OverlayWindowService::class.java).apply {
            action = OverlayWindowService.ACTION_HIDE
        }
        context.startService(intent)
    }

    fun showOverlay(
        context: Context,
        text: String,
        mediaUrl: String?,
        mediaKind: String?,
        untilDismissed: Boolean,
        durationSec: Int,
        opacity: Double,
    ) {
        val intent = Intent(context, OverlayWindowService::class.java).apply {
            action = OverlayWindowService.ACTION_SHOW
            putExtra(OverlayWindowService.EXTRA_TEXT, text)
            putExtra(OverlayWindowService.EXTRA_MEDIA_URL, mediaUrl)
            putExtra(OverlayWindowService.EXTRA_MEDIA_KIND, mediaKind)
            putExtra(OverlayWindowService.EXTRA_UNTIL_DISMISSED, untilDismissed)
            putExtra(OverlayWindowService.EXTRA_DURATION_SEC, durationSec)
            putExtra(OverlayWindowService.EXTRA_OPACITY, opacity)
        }
        context.startService(intent)
    }

    private fun wakeScreen(context: Context) {
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            val wl = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                "vertisignage:relayWake",
            )
            wl.acquire(4000L)
        } catch (_: Exception) {
        }
    }

    private fun dismissKeyguard(context: Context, activity: Activity?) {
        try {
            val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            if (activity != null) {
                km.requestDismissKeyguard(activity, null)
            }
        } catch (_: Exception) {
        }
    }
}
