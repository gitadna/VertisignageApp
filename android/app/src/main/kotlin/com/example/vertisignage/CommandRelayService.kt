package com.example.vertisignage

import android.app.Service
import android.content.Intent
import android.os.IBinder

class CommandRelayService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            CommandRelay.ACTION_WAKE -> {
                CommandRelay.wakeApp(this)
            }
            CommandRelay.ACTION_OVERLAY_SHOW -> {
                val text = intent.getStringExtra(CommandRelay.EXTRA_TEXT).orEmpty().ifBlank {
                    "VertiSignage"
                }
                val mediaUrl = intent.getStringExtra(CommandRelay.EXTRA_MEDIA_URL)
                val mediaKind = intent.getStringExtra(CommandRelay.EXTRA_MEDIA_KIND)
                val untilDismissed = intent.getBooleanExtra(CommandRelay.EXTRA_UNTIL_DISMISSED, true)
                val durationSec = intent.getIntExtra(CommandRelay.EXTRA_DURATION_SEC, 10)
                val opacity = intent.getDoubleExtra(CommandRelay.EXTRA_OPACITY, 0.9)
                CommandRelay.showOverlay(
                    context = this,
                    text = text,
                    mediaUrl = mediaUrl,
                    mediaKind = mediaKind,
                    untilDismissed = untilDismissed,
                    durationSec = durationSec,
                    opacity = opacity,
                )
                // Bring signage to foreground after overlay request.
                CommandRelay.wakeApp(this)
            }
            CommandRelay.ACTION_OVERLAY_HIDE -> {
                CommandRelay.hideOverlay(this)
            }
        }
        stopSelf(startId)
        return START_NOT_STICKY
    }
}
