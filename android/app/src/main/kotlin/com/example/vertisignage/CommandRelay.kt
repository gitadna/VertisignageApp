package com.example.vertisignage

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

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

    fun wakeApp(context: Context): Boolean {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        if (launch != null) {
            try {
                launch.addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
                )
                context.startActivity(launch)
                return true
            } catch (_: Exception) {
                // Fall back to explicit activity launch below.
            }
        }

        return try {
            val explicit = Intent(context, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
                )
            }
            context.startActivity(explicit)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun hideOverlay(context: Context) {
        context.stopService(Intent(context, OverlayWindowService::class.java))
    }

    fun showOverlay(
        context: Context,
        text: String,
        mediaUrl: String?,
        mediaKind: String?,
        untilDismissed: Boolean,
        durationSec: Int,
        opacity: Double,
        scheduleEndEpochMs: Long = 0L,
    ) {
        val intent = Intent(context, OverlayWindowService::class.java).apply {
            action = OverlayWindowService.ACTION_SHOW
            putExtra(OverlayWindowService.EXTRA_TEXT, text)
            putExtra(OverlayWindowService.EXTRA_MEDIA_URL, mediaUrl)
            putExtra(OverlayWindowService.EXTRA_MEDIA_KIND, mediaKind)
            putExtra(OverlayWindowService.EXTRA_UNTIL_DISMISSED, untilDismissed)
            putExtra(OverlayWindowService.EXTRA_DURATION_SEC, durationSec)
            putExtra(OverlayWindowService.EXTRA_OPACITY, opacity)
            putExtra(OverlayWindowService.EXTRA_SCHEDULE_END_EPOCH_MS, scheduleEndEpochMs)
        }
        ContextCompat.startForegroundService(context, intent)
    }

}
