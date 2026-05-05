package com.example.vertisignage

import android.app.Service
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.FrameLayout
import android.widget.TextView
import android.widget.VideoView
import java.net.URL
import java.util.concurrent.Executors

class OverlayWindowService : Service() {
    private var wm: WindowManager? = null
    private var overlayRoot: FrameLayout? = null
    private var overlayText: TextView? = null
    private var overlayImage: ImageView? = null
    private var overlayVideo: VideoView? = null
    private val ui = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var autoHide: Runnable? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        return when (action) {
            ACTION_SHOW -> {
                val text = intent.getStringExtra(EXTRA_TEXT).orEmpty()
                val mediaUrl = intent.getStringExtra(EXTRA_MEDIA_URL)
                val mediaKind = intent.getStringExtra(EXTRA_MEDIA_KIND)
                val untilDismissed = intent.getBooleanExtra(EXTRA_UNTIL_DISMISSED, true)
                val durationSec = intent.getIntExtra(EXTRA_DURATION_SEC, 10)
                val opacity = intent.getDoubleExtra(EXTRA_OPACITY, 0.9)
                showOverlay(
                    message = text.ifBlank { "VertiSignage" },
                    mediaUrl = mediaUrl,
                    mediaKind = mediaKind,
                    untilDismissed = untilDismissed,
                    durationSec = durationSec,
                    opacity = opacity.toFloat(),
                )
                START_STICKY
            }
            ACTION_HIDE -> {
                hideOverlay()
                stopSelf()
                START_NOT_STICKY
            }
            else -> START_STICKY
        }
    }

    override fun onDestroy() {
        autoHide?.let { ui.removeCallbacks(it) }
        autoHide = null
        hideOverlay()
        io.shutdownNow()
        super.onDestroy()
    }

    private fun showOverlay(
        message: String,
        mediaUrl: String?,
        mediaKind: String?,
        untilDismissed: Boolean,
        durationSec: Int,
        opacity: Float,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !Settings.canDrawOverlays(this)
        ) {
            return
        }
        val bgOpacity = (opacity.coerceIn(0.5f, 1f) * 255).toInt()
        if (overlayRoot != null) {
            overlayText?.text = message
            overlayRoot?.setBackgroundColor(Color.argb(bgOpacity, 0, 0, 0))
            bindMedia(mediaUrl, mediaKind)
            scheduleAutoHide(untilDismissed, durationSec)
            return
        }
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.argb(bgOpacity, 0, 0, 0))
        }
        val image = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            visibility = View.GONE
            setBackgroundColor(Color.TRANSPARENT)
        }
        val video = VideoView(this).apply {
            visibility = View.GONE
            setBackgroundColor(Color.TRANSPARENT)
        }
        val tv = TextView(this).apply {
            text = message
            textSize = 24f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = Gravity.CENTER
        }
        root.addView(
            image,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        root.addView(
            video,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        root.addView(
            tv,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        val type =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )
        params.gravity = Gravity.TOP or Gravity.START
        wm?.addView(root, params)
        overlayRoot = root
        overlayText = tv
        overlayImage = image
        overlayVideo = video
        bindMedia(mediaUrl, mediaKind)
        scheduleAutoHide(untilDismissed, durationSec)
    }

    private fun hideOverlay() {
        autoHide?.let { ui.removeCallbacks(it) }
        autoHide = null
        overlayVideo?.stopPlayback()
        overlayRoot?.let { root ->
            wm?.removeView(root)
        }
        overlayRoot = null
        overlayText = null
        overlayImage = null
        overlayVideo = null
    }

    private fun bindMedia(mediaUrl: String?, mediaKind: String?) {
        val image = overlayImage ?: return
        val video = overlayVideo ?: return
        val url = mediaUrl?.trim()
        if (url.isNullOrEmpty() || mediaKind == null) {
            image.visibility = View.GONE
            video.visibility = View.GONE
            video.stopPlayback()
            return
        }

        if (mediaKind == "video") {
            image.visibility = View.GONE
            video.visibility = View.VISIBLE
            try {
                video.setVideoPath(url)
                video.setOnPreparedListener { mp ->
                    mp.isLooping = true
                    video.start()
                }
                video.setOnErrorListener { _, _, _ -> true }
            } catch (_: Exception) {
                video.visibility = View.GONE
            }
            return
        }

        video.visibility = View.GONE
        video.stopPlayback()
        image.visibility = View.VISIBLE
        io.execute {
            try {
                val bmp = URL(url).openStream().use { BitmapFactory.decodeStream(it) }
                ui.post {
                    if (overlayImage != null && bmp != null) {
                        overlayImage?.setImageBitmap(bmp)
                    }
                }
            } catch (_: Exception) {
                ui.post { overlayImage?.visibility = View.GONE }
            }
        }
    }

    private fun scheduleAutoHide(untilDismissed: Boolean, durationSec: Int) {
        autoHide?.let { ui.removeCallbacks(it) }
        autoHide = null
        if (untilDismissed) return
        autoHide = Runnable {
            hideOverlay()
            stopSelf()
        }
        ui.postDelayed(autoHide!!, durationSec.coerceIn(3, 1200) * 1000L)
    }

    companion object {
        const val ACTION_SHOW = "overlay_show"
        const val ACTION_HIDE = "overlay_hide"
        const val EXTRA_TEXT = "text"
        const val EXTRA_MEDIA_URL = "mediaUrl"
        const val EXTRA_MEDIA_KIND = "mediaKind"
        const val EXTRA_UNTIL_DISMISSED = "untilDismissed"
        const val EXTRA_DURATION_SEC = "durationSec"
        const val EXTRA_OPACITY = "opacity"
    }
}
