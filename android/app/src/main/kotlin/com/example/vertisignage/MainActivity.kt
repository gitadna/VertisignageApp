package com.example.vertisignage

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.os.PowerManager
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
                    "restartApp" -> {
                        restartApp()
                        result.success(null)
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

    private fun restartApp() {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        startActivity(intent)
        finish()
        Runtime.getRuntime().exit(0)
    }

    private fun installApkFile(file: File): Boolean = try {
        if (!file.exists()) return false
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
}
