package com.example.vertisignage

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Structured recovery analytics: logcat ([FleetTelemetry]) + best-effort Dart ([RemoteLogUploader]).
 */
object RecoveryAnalyticsEmitter {
    const val CHANNEL = "vertisignage/recovery_analytics"

    const val EXTRA_RECOVERY_ATTEMPT_ID = "extra_recovery_attempt_id"

    const val RESULT_SUCCESS = "success"
    const val RESULT_FAILED = "failed"
    const val RESULT_SUPPRESSED = "suppressed"
    const val RESULT_COOLDOWN_BLOCKED = "cooldown_blocked"
    const val RESULT_LOOP_GUARD_BLOCKED = "loop_guard_blocked"

    fun newAttemptId(): String = UUID.randomUUID().toString()

    fun oemFields(context: Context): Map<String, Any?> =
        mapOf(
            "manufacturer" to (Build.MANUFACTURER ?: "unknown"),
            "model" to (Build.MODEL ?: "unknown"),
            "api" to Build.VERSION.SDK_INT,
            "current_visibility_state" to WatchdogState.uiVisibilityState(context.applicationContext),
        )

    fun postToFlutter(
        app: Context,
        message: String,
        meta: Map<String, Any?>,
    ) {
        val merged = LinkedHashMap<String, Any?>(meta.size + 4)
        merged.putAll(oemFields(app))
        merged.putAll(meta)
        val detail =
            buildString {
                append("msg=").append(message)
                for ((k, v) in merged) {
                    append(' ').append(k).append('=').append(v)
                }
            }
        FleetTelemetry.log(app.applicationContext, "recovery_analytics", detail)
        invokeDart(app.applicationContext, message, merged)
    }

    private fun invokeDart(
        app: Context,
        message: String,
        meta: Map<String, Any?>,
    ) {
        try {
            Handler(Looper.getMainLooper()).post {
                try {
                    val engine: FlutterEngine = VertiSignageApp.cachedEngine() ?: return@post
                    val payload = HashMap<String, Any?>(meta.size + 2)
                    payload.putAll(meta)
                    payload["message"] = message
                    MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).invokeMethod(
                        "event",
                        payload,
                        object : MethodChannel.Result {
                            override fun success(result: Any?) = Unit

                            override fun error(
                                errorCode: String,
                                errorMessage: String?,
                                errorDetails: Any?,
                            ) {
                                Log.w(TAG, "recovery_analytics_dart_error $errorCode $errorMessage")
                            }

                            override fun notImplemented() = Unit
                        },
                    )
                } catch (t: Throwable) {
                    Log.w(TAG, "recovery_analytics_invoke_failed ${t::class.java.simpleName}")
                }
            }
        } catch (_: Throwable) {
        }
    }

    fun emitRecoveryStarted(
        context: Context,
        attemptId: String,
        triggerSource: String,
        legacyReason: String?,
        recoveryMethodUsed: String,
    ) {
        postToFlutter(
            context,
            "recovery_started",
            mapOf(
                "recovery_attempt_id" to attemptId,
                "recovery_trigger_source" to triggerSource,
                "legacy_reason" to (legacyReason ?: ""),
                "recovery_method_used" to recoveryMethodUsed,
                "recovery_result" to "success",
            ),
        )
    }

    fun emitRecoveryCompleted(
        context: Context,
        attemptId: String,
        triggerSource: String,
        recoveryMethodUsed: String,
        recoveryResult: String,
        timeToVisibleMs: Long?,
        timeToBackgroundRuntimeMs: Long?,
        legacyReason: String?,
        additionalMeta: Map<String, Any?>? = null,
    ) {
        val m = LinkedHashMap<String, Any?>()
        m["recovery_attempt_id"] = attemptId
        m["recovery_trigger_source"] = triggerSource
        m["recovery_method_used"] = recoveryMethodUsed
        m["recovery_result"] = recoveryResult
        if (timeToVisibleMs != null) m["time_to_visible_ms"] = timeToVisibleMs
        if (timeToBackgroundRuntimeMs != null) m["time_to_background_runtime_ms"] = timeToBackgroundRuntimeMs
        m["legacy_reason"] = legacyReason ?: ""
        additionalMeta?.let { m.putAll(it) }
        postToFlutter(context, "recovery_completed", m)
    }

    fun emitAdminTimeline(
        context: Context,
        message: String,
        meta: Map<String, Any?>,
    ) {
        val m = LinkedHashMap<String, Any?>()
        m.putAll(meta)
        postToFlutter(context, message, m)
    }

    private const val TAG = "VertiSignageBG"
}
