package com.example.vertisignage

import android.app.Activity
import android.app.Application
import android.content.ComponentCallbacks2
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Process-wide entrypoint.
 *
 * Responsibilities (all best-effort and crash-safe):
 *  - Stamp `app_oncreate_at_ms` for the boot-timing trail.
 *  - Record the process-start in [RecoveryLoopGuard] so callers can dampen restart storms.
 *  - Pre-load Flutter's native library and (when safe) cache a warm [FlutterEngine] so that
 *    [MainActivity] can attach instantly through `provideFlutterEngine` instead of cold-starting
 *    Dart on the main thread.
 *  - Track foreground/background visibility transitions so we can suppress duplicate wake chains
 *    and surface diagnostics. Uses [Application.ActivityLifecycleCallbacks] to avoid adding a
 *    new lifecycle-process dependency.
 *
 * Hard constraints from the architecture plan:
 *  - NEVER throw from any phase here; engine cache failure must fall back silently to the
 *    cold-start path in [MainActivity.provideFlutterEngine].
 *  - The Dart entrypoint executed during prewarm is the application's `main()`. Per the staged
 *    bootstrap plan, `main()` runs only the lightweight critical bootstrap before `runApp` and
 *    defers heavy init (Firebase, websocket, OTA, push, etc.) to a post-first-frame callback.
 *    Do NOT add any heavy native work to this class — keep [Application.onCreate] cheap.
 */
class VertiSignageApp : Application() {

    private val visibleActivities = AtomicInteger(0)
    private val cachedEnginePrewarmed = AtomicBoolean(false)

    override fun onCreate() {
        super.onCreate()
        BootTiming.markAppOnCreate(this)
        try {
            RecoveryLoopGuard.recordProcessStart(this)
        } catch (_: Throwable) {
            // diagnostics only
        }
        FleetTelemetry.log(this, "app_oncreate", loopDetail())
        prewarmFlutter()
        installVisibilityObserver()
        installTrimMemoryObserver()
    }

    /**
     * Inline crash-safe prewarm: load libflutter.so eagerly, build a [FlutterEngine], execute the
     * default Dart entrypoint, and register the engine under [CACHED_ENGINE_ID] before
     * Application.onCreate returns so the very first [MainActivity.provideFlutterEngine] call
     * picks it up and avoids cold-starting Dart.
     *
     * Why inline (not Handler.post): a posted callback runs AFTER MainActivity.onCreate on the
     * same main thread, which means provideFlutterEngine would see a cache miss on every regular
     * launcher-icon launch (the cache hit only matters for the very first attach). We accept the
     * extra ~300-700ms in Application.onCreate; the FGS 5-second start window from
     * KioskForegroundService.onCreate is far larger than that even on slow OEMs.
     *
     * If anything throws we fall back to default cold-start without disturbing recovery flow.
     */
    private fun prewarmFlutter() {
        if (!cachedEnginePrewarmed.compareAndSet(false, true)) return
        try {
            FlutterInjector.instance().flutterLoader().startInitialization(this)
        } catch (t: Throwable) {
            Log.w(TAG, "event=flutter_loader_start_failed source=VertiSignageApp msg=${t::class.java.simpleName}:${t.message}")
            FleetTelemetry.log(this, "engine_cache_prewarm_failed", "loader_start:${t::class.java.simpleName}")
            return
        }
        try {
            val engine = FlutterEngine(this)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(),
            )
            FlutterEngineCache.getInstance().put(CACHED_ENGINE_ID, engine)
            BootTiming.markEngineCached(this)
            val deltaMs = BootTiming.deltaSince(BootTiming.appOnCreateAtMs(this))
            FleetTelemetry.log(this, "engine_cache_prewarmed", "deltaSinceAppOnCreateMs=$deltaMs")
        } catch (t: Throwable) {
            Log.w(TAG, "event=engine_cache_prewarm_failed source=VertiSignageApp msg=${t::class.java.simpleName}:${t.message}")
            FleetTelemetry.log(this, "engine_cache_prewarm_failed", "engine_build:${t::class.java.simpleName}")
        }
    }

    private fun installTrimMemoryObserver() {
        try {
            registerComponentCallbacks(
                object : ComponentCallbacks2 {
                    override fun onTrimMemory(level: Int) {
                        if (level < ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) return
                        try {
                            FleetTelemetry.log(
                                applicationContext,
                                "m4_trim_memory",
                                "level=$level",
                            )
                            PresentationRecoveryCoordinator.notifyTrigger(
                                applicationContext,
                                "on_trim_memory_$level",
                            )
                        } catch (_: Throwable) {
                        }
                    }

                    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) = Unit

                    @Deprecated("Deprecated in Java")
                    override fun onLowMemory() = Unit
                },
            )
        } catch (t: Throwable) {
            Log.w(TAG, "event=trim_memory_observer_failed source=VertiSignageApp msg=${t::class.java.simpleName}:${t.message}")
        }
    }

    private fun installVisibilityObserver() {
        try {
            registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
                override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
                override fun onActivityStarted(activity: Activity) {
                    if (visibleActivities.incrementAndGet() == 1) {
                        FleetTelemetry.log(applicationContext, "app_foreground", activity.javaClass.simpleName)
                    }
                }
                override fun onActivityResumed(activity: Activity) = Unit
                override fun onActivityPaused(activity: Activity) = Unit
                override fun onActivityStopped(activity: Activity) {
                    if (visibleActivities.decrementAndGet() <= 0) {
                        visibleActivities.set(0)
                        FleetTelemetry.log(applicationContext, "app_background", activity.javaClass.simpleName)
                    }
                }
                override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
                override fun onActivityDestroyed(activity: Activity) = Unit
            })
        } catch (t: Throwable) {
            Log.w(TAG, "event=visibility_observer_install_failed source=VertiSignageApp msg=${t::class.java.simpleName}:${t.message}")
        }
    }

    private fun loopDetail(): String {
        return try {
            val inLoop = RecoveryLoopGuard.inLoop(this)
            val recent = RecoveryLoopGuard.snapshot(this).size
            "loop=$inLoop recent=$recent api=${Build.VERSION.SDK_INT}"
        } catch (_: Throwable) {
            "loop=unknown"
        }
    }

    companion object {
        /** Cache key for the prewarmed engine. Must match the lookup in [MainActivity]. */
        const val CACHED_ENGINE_ID = "vertisignage_main_engine"
        private const val TAG = "VertiSignageBG"

        /** Convenience: lookup the cached engine if and only if it is still present. */
        fun cachedEngine(): FlutterEngine? = try {
            FlutterEngineCache.getInstance().get(CACHED_ENGINE_ID)
        } catch (_: Throwable) {
            null
        }
    }
}
