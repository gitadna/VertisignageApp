package com.example.vertisignage

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.content.pm.ServiceInfo
import android.provider.Settings
import android.media.MediaPlayer
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.ImageView
import android.widget.FrameLayout
import android.widget.TextView
import android.widget.VideoView
import androidx.core.app.NotificationCompat
import java.net.URL
import java.util.concurrent.Executors

class OverlayWindowService : Service() {
    private var wm: WindowManager? = null
    private var overlayRoot: FrameLayout? = null
    private var overlayText: TextView? = null
    private var overlayImage: ImageView? = null
    private var overlayVideo: VideoView? = null
    private var overlayWeb: WebView? = null
    private val ui = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var autoHide: Runnable? = null

    override fun onCreate() {
        super.onCreate()
        createChannelIfNeeded()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        return when (action) {
            ACTION_SHOW -> {
                startAsForeground()
                val text = intent.getStringExtra(EXTRA_TEXT).orEmpty()
                val mediaUrl = intent.getStringExtra(EXTRA_MEDIA_URL)
                val mediaKind = intent.getStringExtra(EXTRA_MEDIA_KIND)
                val untilDismissed = intent.getBooleanExtra(EXTRA_UNTIL_DISMISSED, true)
                val durationSec = intent.getIntExtra(EXTRA_DURATION_SEC, 10)
                val opacity = intent.getDoubleExtra(EXTRA_OPACITY, 0.9)
                val scheduleEndEpochMs = intent.getLongExtra(EXTRA_SCHEDULE_END_EPOCH_MS, 0L)
                showOverlay(
                    message = text.ifBlank { "VertiSignage" },
                    mediaUrl = mediaUrl,
                    mediaKind = mediaKind,
                    untilDismissed = untilDismissed,
                    durationSec = durationSec,
                    opacity = opacity.toFloat(),
                    scheduleEndEpochMs = scheduleEndEpochMs,
                )
                START_STICKY
            }
            ACTION_HIDE -> {
                hideOverlay()
                stopForeground(STOP_FOREGROUND_REMOVE)
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
        stopForeground(STOP_FOREGROUND_REMOVE)
        io.shutdownNow()
        super.onDestroy()
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "VertiSignage announcement overlay",
            NotificationManager.IMPORTANCE_HIGH,
        )
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(channel)
    }

    private fun startAsForeground() {
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
            .setContentText("Announcement showing")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

    private fun showOverlay(
        message: String,
        mediaUrl: String?,
        mediaKind: String?,
        untilDismissed: Boolean,
        durationSec: Int,
        opacity: Float,
        scheduleEndEpochMs: Long,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !Settings.canDrawOverlays(this)
        ) {
            log("overlay_permission_missing", "show_blocked")
            RecoveryScheduler.enqueueNow(applicationContext, "overlay_permission_missing")
            CommandRelay.wakeApp(this)
            return
        }
        val bgOpacity = (opacity.coerceIn(0.5f, 1f) * 255).toInt()
        if (overlayRoot != null) {
            overlayText?.text = message
            overlayRoot?.setBackgroundColor(Color.argb(bgOpacity, 0, 0, 0))
            bindMedia(mediaUrl, mediaKind)
            scheduleAutoHide(untilDismissed, durationSec, scheduleEndEpochMs)
            return
        }
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.argb(bgOpacity, 0, 0, 0))
        }
        val image = ImageView(this).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            visibility = View.GONE
            setBackgroundColor(Color.TRANSPARENT)
        }
        val web = WebView(this).apply {
            visibility = View.GONE
            setBackgroundColor(Color.BLACK)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            webViewClient =
                object : WebViewClient() {
                    override fun onReceivedError(
                        view: WebView?,
                        errorCode: Int,
                        description: String?,
                        failingUrl: String?,
                    ) {
                        if (!failingUrl.isNullOrBlank()) {
                            hideTextForMedia()
                        }
                    }
                }
            webChromeClient = WebChromeClient()
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
            web,
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
        try {
            wm?.addView(root, params)
        } catch (t: Throwable) {
            log("overlay_add_view_failed", "${t::class.java.simpleName}:${t.message}")
            RecoveryScheduler.enqueueNow(applicationContext, "overlay_add_view_failed")
            CommandRelay.wakeApp(this)
            return
        }
        overlayRoot = root
        overlayText = tv
        overlayImage = image
        overlayVideo = video
        overlayWeb = web
        bindMedia(mediaUrl, mediaKind)
        scheduleAutoHide(untilDismissed, durationSec, scheduleEndEpochMs)
        log("overlay_shown", "kind=${mediaKind ?: "auto"} untilDismissed=$untilDismissed")
    }

    private fun hideOverlay() {
        autoHide?.let { ui.removeCallbacks(it) }
        autoHide = null
        overlayVideo?.stopPlayback()
        overlayWeb?.stopLoading()
        overlayWeb?.loadUrl("about:blank")
        overlayWeb?.destroy()
        overlayRoot?.let { root ->
            wm?.removeView(root)
        }
        overlayRoot = null
        overlayText = null
        overlayImage = null
        overlayVideo = null
        overlayWeb = null
        log("overlay_hidden", "ok")
    }

    private fun bindMedia(mediaUrl: String?, mediaKind: String?) {
        val image = overlayImage ?: return
        val video = overlayVideo ?: return
        val web = overlayWeb
        val text = overlayText
        val url = mediaUrl?.trim()
        if (url.isNullOrEmpty()) {
            image.visibility = View.GONE
            video.visibility = View.GONE
            web?.visibility = View.GONE
            video.stopPlayback()
            text?.visibility = View.VISIBLE
            return
        }

        val normalizedKind = when (mediaKind?.trim()?.lowercase()) {
            "video" -> "video"
            "image" -> "image"
            "url" -> "url"
            else -> inferMediaKindFromUrl(url)
        }

        if (normalizedKind == "video") {
            image.visibility = View.GONE
            video.visibility = View.VISIBLE
            web?.visibility = View.GONE
            text?.visibility = View.GONE
            try {
                video.setVideoPath(url)
                video.setOnPreparedListener { mp ->
                    mp.isLooping = true
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
                        mp.setVideoScalingMode(MediaPlayer.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING)
                    }
                    video.start()
                }
                video.setOnErrorListener { _, _, _ ->
                    video.visibility = View.GONE
                    hideTextForMedia()
                    true
                }
            } catch (_: Exception) {
                video.visibility = View.GONE
                hideTextForMedia()
            }
            return
        }

        if (normalizedKind == "url") {
            image.visibility = View.GONE
            video.visibility = View.GONE
            video.stopPlayback()
            web?.visibility = View.VISIBLE
            text?.visibility = View.GONE
            try {
                web?.loadUrl(url)
            } catch (_: Exception) {
                web?.visibility = View.GONE
                hideTextForMedia()
            }
            return
        }

        video.visibility = View.GONE
        video.stopPlayback()
        web?.visibility = View.GONE
        image.visibility = View.VISIBLE
        text?.visibility = View.GONE
        io.execute {
            try {
                val bmp = URL(url).openStream().use { BitmapFactory.decodeStream(it) }
                ui.post {
                    if (overlayImage != null && bmp != null) {
                        overlayImage?.setImageBitmap(bmp)
                        text?.visibility = View.GONE
                    } else {
                        overlayImage?.visibility = View.GONE
                        hideTextForMedia()
                    }
                }
            } catch (_: Exception) {
                ui.post {
                    overlayImage?.visibility = View.GONE
                    hideTextForMedia()
                }
            }
        }
    }

    private fun hideTextForMedia() {
        overlayText?.visibility = View.GONE
    }

    private fun inferMediaKindFromUrl(url: String): String {
        val noQuery = url.substringBefore('?').lowercase()
        return when {
            noQuery.endsWith(".mp4") ||
                noQuery.endsWith(".m3u8") ||
                noQuery.endsWith(".webm") ||
                noQuery.endsWith(".mov") -> "video"
            else -> "image"
        }
    }

    /**
     * Hide overlay when [scheduleEndEpochMs] is reached (looping media until then), when wall-clock
     * duration elapses if not [untilDismissed], or never until service hide when [untilDismissed]
     * and no schedule end.
     */
    private fun scheduleAutoHide(
        untilDismissed: Boolean,
        durationSec: Int,
        scheduleEndEpochMs: Long,
    ) {
        autoHide?.let { ui.removeCallbacks(it) }
        autoHide = null
        val now = System.currentTimeMillis()

        val deadlineMs =
            when {
                scheduleEndEpochMs > 0L -> scheduleEndEpochMs
                untilDismissed -> 0L
                else -> now + durationSec.coerceIn(3, 1200) * 1000L
            }

        if (deadlineMs <= 0L) return

        val delay = (deadlineMs - now).coerceIn(100L, Long.MAX_VALUE / 4)
        autoHide = Runnable {
            hideOverlay()
            stopSelf()
        }
        ui.postDelayed(autoHide!!, delay)
    }

    companion object {
        private const val NOTIFICATION_ID = 71002
        private const val CHANNEL_ID = "vertisignage_overlay_fg"
        const val ACTION_SHOW = "overlay_show"
        const val ACTION_HIDE = "overlay_hide"
        const val EXTRA_TEXT = "text"
        const val EXTRA_MEDIA_URL = "mediaUrl"
        const val EXTRA_MEDIA_KIND = "mediaKind"
        const val EXTRA_UNTIL_DISMISSED = "untilDismissed"
        const val EXTRA_DURATION_SEC = "durationSec"
        const val EXTRA_OPACITY = "opacity"
        const val EXTRA_SCHEDULE_END_EPOCH_MS = "scheduleEndEpochMs"
        private const val TAG = "VertiSignageBG"
    }

    private fun log(event: String, msg: String, level: Int = Log.INFO) {
        val out =
            buildString {
                append("event=").append(event)
                append(" source=OverlayWindowService")
                append(" api=").append(Build.VERSION.SDK_INT)
                append(" manufacturer=").append(Build.MANUFACTURER ?: "unknown")
                append(" msg=").append(msg)
            }
        when (level) {
            Log.WARN -> Log.w(TAG, out)
            Log.ERROR -> Log.e(TAG, out)
            else -> Log.i(TAG, out)
        }
    }
}
