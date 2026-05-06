package com.example.vertisignage

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.net.Uri
import android.provider.Settings
import android.view.WindowManager
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
    private lateinit var policyManager: DeviceOwnerPolicyManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        policyManager = DeviceOwnerPolicyManager(this)
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
                        result.success(dispatchWakeAppViaForegroundService())
                    }
                    "restartApp" -> {
                        result.success(restartApp())
                    }
                    "showOverlay" -> {
                        val text = call.argument<String>("text") ?: "VertiSignage"
                        val mediaUrl = call.argument<String>("mediaUrl")
                        val mediaKind = call.argument<String>("mediaKind")
                        val untilDismissed = call.argument<Boolean>("untilDismissed") ?: false
                        val durationSec = call.argument<Int>("durationSec") ?: 10
                        val opacity = call.argument<Double>("opacity") ?: 0.9
                        val scheduleEndsAtEpochMs =
                            call.argument<Number>("scheduleEndsAtEpochMs")?.toLong() ?: 0L
                        result.success(
                            showOverlay(
                                text = text,
                                mediaUrl = mediaUrl,
                                mediaKind = mediaKind,
                                untilDismissed = untilDismissed,
                                durationSec = durationSec,
                                opacity = opacity,
                                scheduleEndsAtEpochMs = scheduleEndsAtEpochMs,
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
                        result.success(policyManager.enterLockTask(this))
                    }
                    "stopLockTask" -> {
                        result.success(policyManager.exitLockTask(this))
                    }
                    "isDeviceOwner" -> {
                        result.success(policyManager.isDeviceOwner())
                    }
                    "applyKioskPolicies" -> {
                        result.success(policyManager.applyKioskPolicies())
                    }
                    "clearKioskPolicies" -> {
                        result.success(policyManager.clearKioskPolicies())
                    }
                    "isInLockTask" -> {
                        result.success(policyManager.isInLockTask())
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }
                    "openBatteryOptimizationSettings" -> {
                        result.success(openBatteryOptimizationSettings())
                    }
                    "openAutoStartSettings" -> {
                        result.success(openAutoStartSettings())
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PUSH_BRIDGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "syncPushContext" -> {
                        val api = call.argument<String>("apiBaseUrl")
                        val token = call.argument<String>("accessToken")
                        val deviceId = call.argument<String>("deviceId")
                        PushContextStore.sync(this, api, token, deviceId)
                        result.success(null)
                    }
                    "pushDedupeTryConsume" -> {
                        val id = call.argument<String>("announcementId").orEmpty()
                        if (id.isEmpty()) {
                            result.success(false)
                        } else {
                            result.success(PushDedupe.tryConsume(applicationContext, id))
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

    private fun dispatchWakeAppViaForegroundService(): Boolean {
        return try {
            ContextCompat.startForegroundService(
                this,
                Intent(this, KioskForegroundService::class.java).apply {
                    action = KioskForegroundService.ACTION_WAKE
                },
            )
            true
        } catch (_: Exception) {
            wakeApp()
        }
    }

    private fun wakeApp(): Boolean {
        return CommandRelay.wakeApp(this)
    }

    /**
     * Relaunch this app's launcher activity.
     *
     * Do not call [Runtime.exit] here: it tears down the VM immediately so the new
     * task often never comes up — looks like "app closes but does not restart" on device and emulator.
     */
    private fun restartApp(): Boolean {
        return try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(this, MainActivity::class.java)
            intent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK,
            )
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
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
        private const val PUSH_BRIDGE_CHANNEL = "vertisignage/push_bridge"
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun openBatteryOptimizationSettings(): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            startActivity(
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            true
        } else {
            false
        }
    } catch (_: Exception) {
        false
    }

    private fun openAutoStartSettings(): Boolean {
        val candidates = listOf(
            Intent().setClassName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            ),
            Intent().setClassName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            ),
            Intent().setClassName(
                "com.oppo.safe",
                "com.oppo.safe.permission.startup.StartupAppListActivity",
            ),
            Intent().setClassName(
                "com.iqoo.secure",
                "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            ),
            Intent().setClassName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            ),
        )

        for (intent in candidates) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    return true
                }
            } catch (_: Exception) {
                // try next vendor-specific settings activity
            }
        }

        return try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", packageName, null)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            true
        } catch (_: Exception) {
            false
        }
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
        scheduleEndsAtEpochMs: Long = 0L,
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
            scheduleEndEpochMs = scheduleEndsAtEpochMs,
        )
        wakeApp()
        return true
    }

    private fun hideOverlay() {
        CommandRelay.hideOverlay(this)
    }
}
