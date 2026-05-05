package com.example.vertisignage

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import java.io.File

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setVolume" -> {
                        val percent = call.argument<Int>("percent") ?: 50
                        setVolumePercent(percent)
                        result.success(null)
                    }
                    "setMuted" -> {
                        val muted = call.argument<Boolean>("muted") ?: false
                        setMuted(muted)
                        result.success(null)
                    }
                    "setBrightness" -> {
                        val percent = call.argument<Int>("percent") ?: 100
                        setBrightnessPercent(percent)
                        result.success(null)
                    }
                    "wakeApp" -> {
                        wakeApp()
                        result.success(null)
                    }
                    "restartApp" -> {
                        restartApp()
                        result.success(null)
                    }
                    "showOverlay" -> {
                        val text = call.argument<String>("text") ?: "VertiSignage"
                        val mediaUrl = call.argument<String>("mediaUrl")
                        val mediaKind = call.argument<String>("mediaKind")
                        val untilDismissed = call.argument<Boolean>("untilDismissed") ?: true
                        val durationSec = call.argument<Int>("durationSec") ?: 10
                        val opacity = call.argument<Double>("opacity") ?: 0.9
                        result.success(
                            showOverlay(
                                text = text,
                                mediaUrl = mediaUrl,
                                mediaKind = mediaKind,
                                untilDismissed = untilDismissed,
                                durationSec = durationSec,
                                opacity = opacity,
                            ),
                        )
                    }
                    "hideOverlay" -> {
                        hideOverlay()
                        result.success(true)
                    }
                    "canDrawOverlays" -> {
                        result.success(canDrawOverlays())
                    }
                    "rebootDevice" -> {
                        result.success(tryReboot())
                    }
                    "startLockTask" -> {
                        result.success(tryStartLockTask())
                    }
                    "stopLockTask" -> {
                        result.success(tryStopLockTask())
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.success(false)
                        } else {
                            result.success(installApkFile(File(path)))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KIOSK_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForeground" -> {
                        ContextCompat.startForegroundService(
                            this,
                            Intent(this, KioskForegroundService::class.java),
                        )
                        result.success(null)
                    }
                    "stopForeground" -> {
                        stopService(Intent(this, KioskForegroundService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun tryStartLockTask(): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            startLockTask()
        }
        true
    } catch (_: Exception) {
        false
    }

    private fun tryStopLockTask(): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            stopLockTask()
        }
        true
    } catch (_: Exception) {
        false
    }

    override fun onPostResume() {
        super.onPostResume()
        hideSystemUi()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemUi()
    }

    private fun hideSystemUi() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val c = WindowInsetsControllerCompat(window, window.decorView)
        c.hide(WindowInsetsCompat.Type.systemBars())
        c.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    }

    private fun setVolumePercent(percent: Int) {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val idx = (percent.coerceIn(0, 100) * max / 100f).toInt()
        am.setStreamVolume(AudioManager.STREAM_MUSIC, idx, 0)
    }

    private fun setMuted(muted: Boolean) {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.adjustStreamVolume(
            AudioManager.STREAM_MUSIC,
            if (muted) AudioManager.ADJUST_MUTE else AudioManager.ADJUST_UNMUTE,
            0,
        )
    }

    private fun setBrightnessPercent(percent: Int) {
        val lp = window.attributes
        lp.screenBrightness = (percent.coerceIn(1, 100) / 100f)
        window.attributes = lp
    }

    private fun wakeApp() {
        CommandRelay.wakeApp(this, this)
    }

    /**
     * Relaunch this app's launcher activity.
     *
     * Do not call [Runtime.exit] here: it tears down the VM immediately so the new
     * task often never comes up — looks like "app closes but does not restart" on device and emulator.
     */
    private fun restartApp() {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return
        intent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK,
        )
        startActivity(intent)
        finishAffinity()
    }

    private fun installApkFile(file: File): Boolean = try {
        if (!file.exists()) {
            false
        } else {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            true
        }
    } catch (_: Exception) {
        false
    }

    private fun tryReboot(): Boolean = try {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        pm.reboot(null)
        true
    } catch (_: Exception) {
        false
    }

    companion object {
        private const val DEVICE_CHANNEL = "vertisignage/device"
        private const val KIOSK_CHANNEL = "vertisignage/kiosk"
    }

    private fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun showOverlay(
        text: String,
        mediaUrl: String?,
        mediaKind: String?,
        untilDismissed: Boolean,
        durationSec: Int,
        opacity: Double,
    ): Boolean {
        if (!canDrawOverlays()) return false
        CommandRelay.showOverlay(
            context = this,
            text = text,
            mediaUrl = mediaUrl,
            mediaKind = mediaKind,
            untilDismissed = untilDismissed,
            durationSec = durationSec,
            opacity = opacity,
        )
        wakeApp()
        return true
    }

    private fun hideOverlay() {
        CommandRelay.hideOverlay(this)
    }
}
