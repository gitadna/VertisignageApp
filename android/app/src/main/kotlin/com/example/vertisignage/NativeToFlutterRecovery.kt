package com.example.vertisignage

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Invokes Dart-side surface recovery on the cached Flutter engine (main isolate).
 * Must run on the main thread for the engine messenger.
 */
object NativeToFlutterRecovery {
    const val CHANNEL = "vertisignage/recovery_from_native"
    private const val TAG = "VertiSignageBG"

    fun postRecoverPresentationSurface(app: Context) {
        try {
            Handler(Looper.getMainLooper()).post {
                try {
                    val engine: FlutterEngine = VertiSignageApp.cachedEngine() ?: run {
                        FleetTelemetry.log(app, "m4_recovery_result", "stage3_no_engine")
                        return@post
                    }
                    MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).invokeMethod(
                        "recoverPresentationSurface",
                        null,
                        object : MethodChannel.Result {
                            override fun success(result: Any?) {
                                FleetTelemetry.log(app, "m4_recovery_result", "stage3_dart_ok")
                            }

                            override fun error(
                                errorCode: String,
                                errorMessage: String?,
                                errorDetails: Any?,
                            ) {
                                FleetTelemetry.log(
                                    app,
                                    "m4_recovery_result",
                                    "stage3_dart_error=${errorMessage ?: errorCode}",
                                )
                            }

                            override fun notImplemented() {
                                FleetTelemetry.log(app, "m4_recovery_result", "stage3_dart_not_implemented")
                            }
                        },
                    )
                } catch (t: Throwable) {
                    Log.w(TAG, "event=m4_native_to_flutter_failed msg=${t::class.java.simpleName}:${t.message}")
                    FleetTelemetry.log(
                        app,
                        "m4_recovery_result",
                        "stage3_invoke_failed=${t::class.java.simpleName}",
                    )
                }
            }
        } catch (_: Throwable) {
        }
    }
}
