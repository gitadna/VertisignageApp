package com.example.vertisignage

import android.content.Context
import android.content.Intent
import android.app.AlarmManager
import android.app.PendingIntent
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.net.Uri
import android.provider.Settings
import android.view.WindowManager
import android.util.Log
import androidx.core.content.FileProvider
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var policyManager: DeviceOwnerPolicyManager

    override fun onResume() {
        super.onResume()
        ForegroundWakePolicy.clearUserBackdropHint(applicationContext)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (ForegroundWakePolicy.isRelaxedTeacherMode(applicationContext)) {
            ForegroundWakePolicy.markUserBackdropHint(applicationContext)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        installCrashRestartHandler()
        WatchdogState.markUiHeartbeat(applicationContext)
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
                    "setFirstLaunchCompleted" -> {
                        val completed = call.argument<Boolean>("completed") ?: true
                        result.success(setFirstLaunchCompleted(completed))
                    }
                    "getPendingBootRecovery" -> {
                        result.success(getPendingBootRecovery())
                    }
                    "clearPendingBootRecovery" -> {
                        result.success(clearPendingBootRecovery())
                    }
                    "consumeNativeCrashMarker" -> {
                        result.success(consumeNativeCrashMarker())
                    }
                    "recoveryEnqueueNow" -> {
                        val reason = call.argument<String>("reason") ?: "flutter"
                        RecoveryScheduler.enqueueNow(applicationContext, "flutter:$reason")
                        result.success(true)
                    }
                    "recoveryEnsurePeriodic" -> {
                        val reason = call.argument<String>("reason") ?: "flutter"
                        RecoveryScheduler.ensurePeriodic(applicationContext, "flutter:$reason")
                        result.success(true)
                    }
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
                        val alarmPresentation = call.argument<Boolean>("alarmPresentation") == true
                        result.success(
                            showOverlay(
                                text = text,
                                mediaUrl = mediaUrl,
                                mediaKind = mediaKind,
                                untilDismissed = untilDismissed,
                                durationSec = durationSec,
                                opacity = opacity,
                                scheduleEndsAtEpochMs = scheduleEndsAtEpochMs,
                                alarmPresentation = alarmPresentation,
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
                    "configureForegroundWake" -> {
                        val relaxed = call.argument<Boolean>("relaxedTeacherMode") ?: false
                        ForegroundWakePolicy.setRelaxedTeacherMode(applicationContext, relaxed)
                        result.success(true)
                    }
                    "syncForegroundPresentationState" -> {
                        val wants = call.argument<Boolean>("presentationWantsForeground") ?: false
                        ForegroundWakePolicy.syncPresentationState(applicationContext, wants)
                        result.success(true)
                    }
                    "moveTaskToBack" -> {
                        result.success(moveTaskToRoot())
                    }
                    "schedulePlaylistBoundaryAlarm" -> {
                        val epochMs = (call.argument<Any>("epochMs") as? Number)?.toLong() ?: 0L
                        result.success(
                            if (epochMs > 0L) {
                                PlaylistScheduleAlarm.schedule(this, epochMs)
                            } else {
                                false
                            },
                        )
                    }
                    "cancelPlaylistBoundaryAlarm" -> {
                        PlaylistScheduleAlarm.cancel(this)
                        result.success(true)
                    }
                    "canScheduleExactAlarms" -> {
                        result.success(PlaylistScheduleAlarm.canScheduleExactAlarms(this))
                    }
                    "openExactAlarmSettings" -> {
                        result.success(openExactAlarmSettings())
                    }
                    "prepareManagedClassroomMode" -> {
                        result.success(policyManager.applyManagedClassroomPolicies())
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
        WatchdogState.markUiHeartbeat(applicationContext)
        enforceKioskIfDeviceOwner()
        RecoveryScheduler.enqueueNow(applicationContext, "activity_post_resume")
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            hideSystemUi()
            WatchdogState.markUiHeartbeat(applicationContext)
            enforceKioskIfDeviceOwner()
        }
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

    /** Non-root callers use [moveTaskToBack]; root activity moves the whole task. */
    private fun moveTaskToRoot(): Boolean =
        try {
            moveTaskToBack(true)
        } catch (_: Exception) {
            false
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
        private const val TAG = "VertiSignageBG"
        private val CRASH_HANDLER_INSTALLED = AtomicBoolean(false)
    }

    private fun bgPrefs(): android.content.SharedPreferences {
        val storageContext =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                applicationContext.createDeviceProtectedStorageContext()
            else applicationContext
        return storageContext.getSharedPreferences("vertisignage_bg", Context.MODE_PRIVATE)
    }

    private fun setFirstLaunchCompleted(completed: Boolean): Boolean {
        return try {
            bgPrefs().edit()
                .putBoolean(BootReceiver.KEY_FIRST_LAUNCH_COMPLETED, completed)
                .apply()
            if (completed) {
                // If we had boot events before first launch, try to recover now.
                val pending = bgPrefs().getBoolean(BootReceiver.KEY_PENDING_BOOT_RECOVERY, false)
                if (pending) {
                    RecoveryScheduler.enqueueNow(applicationContext, "first_launch_completed_pending_boot")
                }
                RecoveryScheduler.ensurePeriodic(applicationContext, "first_launch_completed")
            }
            true
        } catch (t: Throwable) {
            Log.w(TAG, "event=set_first_launch_failed source=MainActivity msg=${t::class.java.simpleName}:${t.message}")
            false
        }
    }

    private fun getPendingBootRecovery(): HashMap<String, Any?> {
        return try {
            val prefs = bgPrefs()
            hashMapOf(
                "pending" to prefs.getBoolean(BootReceiver.KEY_PENDING_BOOT_RECOVERY, false),
                "reason" to prefs.getString(BootReceiver.KEY_PENDING_BOOT_RECOVERY_REASON, null),
                "firstLaunchCompleted" to prefs.getBoolean(BootReceiver.KEY_FIRST_LAUNCH_COMPLETED, false),
            )
        } catch (t: Throwable) {
            hashMapOf(
                "pending" to false,
                "reason" to "error:${t::class.java.simpleName}",
                "firstLaunchCompleted" to false,
            )
        }
    }

    private fun clearPendingBootRecovery(): Boolean {
        return try {
            bgPrefs().edit()
                .remove(BootReceiver.KEY_PENDING_BOOT_RECOVERY)
                .remove(BootReceiver.KEY_PENDING_BOOT_RECOVERY_REASON)
                .apply()
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun consumeNativeCrashMarker(): HashMap<String, Any?> {
        return try {
            val prefs = bgPrefs()
            val atMs = prefs.getLong("native_crash_at_ms", 0L)
            val reason = prefs.getString("native_crash_reason", null)
            prefs.edit()
                .remove("native_crash_at_ms")
                .remove("native_crash_reason")
                .apply()
            hashMapOf(
                "crashed" to (atMs > 0L),
                "atMs" to atMs,
                "reason" to reason,
            )
        } catch (t: Throwable) {
            hashMapOf(
                "crashed" to false,
                "reason" to "error:${t::class.java.simpleName}",
            )
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun openBatteryOptimizationSettings(): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val directIntent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (directIntent.resolveActivity(packageManager) != null) {
                startActivity(directIntent)
                true
            } else {
                startActivity(
                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    },
                )
                true
            }
        } else {
            false
        }
    } catch (_: Exception) {
        false
    }

    private fun openAutoStartSettings(): Boolean {
        val candidates = listOf(
            // Xiaomi (MIUI)
            Intent().setClassName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            ),
            // Oppo (ColorOS)
            Intent().setClassName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            ),
            Intent().setClassName(
                "com.oppo.safe",
                "com.oppo.safe.permission.startup.StartupAppListActivity",
            ),
            Intent().setClassName(
                "com.coloros.oppoguardelf",
                "com.coloros.powermanager.fuelgaue.PowerUsageModelActivity",
            ),
            // Vivo / iQOO
            Intent().setClassName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            ),
            Intent().setClassName(
                "com.iqoo.secure",
                "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            ),
            // OnePlus (varies by OxygenOS version; best-effort)
            Intent().setClassName(
                "com.oneplus.security",
                "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
            ),
            Intent().setClassName(
                "com.oneplus.security",
                "com.oneplus.security.chainlaunch.view.ChainLaunchViewPagerActivity",
            ),
            // Samsung (Smart Manager / Device care variants)
            Intent().setClassName(
                "com.samsung.android.lool",
                "com.samsung.android.sm.ui.battery.BatteryActivity",
            ),
            Intent().setClassName(
                "com.samsung.android.sm_cn",
                "com.samsung.android.sm.ui.battery.BatteryActivity",
            ),
            // Realme
            Intent().setClassName(
                "com.realme.safecenter",
                "com.realme.safecenter.permission.startup.StartupAppListActivity",
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

    private fun enforceKioskIfDeviceOwner() {
        try {
            if (!policyManager.isDeviceOwner()) return
            // Teacher / classroom mode: never hijack the screen with lock task.
            if (ForegroundWakePolicy.isRelaxedTeacherMode(applicationContext)) return
            policyManager.applyKioskPolicies()
            if (!policyManager.isInLockTask()) {
                policyManager.enterLockTask(this)
            }
        } catch (_: Throwable) {
            // Best effort: never crash lifecycle on policy re-assertion.
        }
    }

    private fun installCrashRestartHandler() {
        if (!CRASH_HANDLER_INSTALLED.compareAndSet(false, true)) return
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        val appContext = applicationContext
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val reason = "${throwable::class.java.simpleName}:${throwable.message}"
                WatchdogState.recordNativeCrash(appContext, reason)
                RecoveryScheduler.enqueueNow(appContext, "native_crash")
                RecoveryScheduler.scheduleAlarmFallback(appContext, "native_crash", 3_000L)
                val am = appContext.getSystemService(AlarmManager::class.java)
                val launch = Intent(appContext, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                val pi = PendingIntent.getActivity(
                    appContext,
                    29991,
                    launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am?.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, System.currentTimeMillis() + 2_000L, pi)
                } else {
                    @Suppress("DEPRECATION")
                    am?.set(AlarmManager.RTC_WAKEUP, System.currentTimeMillis() + 2_000L, pi)
                }
            } catch (t: Throwable) {
                Log.e(TAG, "event=crash_handler_failed source=MainActivity msg=${t::class.java.simpleName}:${t.message}")
            } finally {
                previous?.uncaughtException(thread, throwable)
                    ?: run {
                        android.os.Process.killProcess(android.os.Process.myPid())
                        kotlin.system.exitProcess(10)
                    }
            }
        }
    }

    private fun openExactAlarmSettings(): Boolean =
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                startActivity(
                    Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                        data = Uri.parse("package:$packageName")
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

    private fun showOverlay(
        text: String,
        mediaUrl: String?,
        mediaKind: String?,
        untilDismissed: Boolean,
        durationSec: Int,
        opacity: Double,
        scheduleEndsAtEpochMs: Long = 0L,
        alarmPresentation: Boolean = false,
    ): Boolean {
        if (!canDrawOverlays()) return false
        ForegroundWakePolicy.syncPresentationState(applicationContext, true)
        val shown = CommandRelay.showOverlay(
            context = this,
            text = text,
            mediaUrl = mediaUrl,
            mediaKind = mediaKind,
            untilDismissed = untilDismissed,
            durationSec = durationSec,
            opacity = opacity,
            scheduleEndEpochMs = scheduleEndsAtEpochMs,
            alarmPresentation = alarmPresentation,
        )
        if (shown) {
            wakeApp()
        }
        return shown
    }

    private fun hideOverlay() {
        CommandRelay.hideOverlay(this)
    }
}
