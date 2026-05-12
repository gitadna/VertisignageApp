package com.example.vertisignage

import android.content.Context
import android.os.Build

object WatchdogState {
    private const val PREFS_NAME = "vertisignage_bg"
    private const val KEY_SERVICE_HEARTBEAT_AT_MS = "service_heartbeat_at_ms"
    private const val KEY_UI_HEARTBEAT_AT_MS = "ui_heartbeat_at_ms"
    private const val KEY_NATIVE_CRASH_AT_MS = "native_crash_at_ms"
    private const val KEY_NATIVE_CRASH_REASON = "native_crash_reason"

    // --- Module 4 (same prefs file; additive keys) ---
    private const val KEY_FLUTTER_RUNTIME_HB_MS = "flutter_runtime_heartbeat_ms"
    private const val KEY_FLUTTER_PLAYER_FRAME_MS = "flutter_player_frame_ms"
    private const val KEY_FLUTTER_ROUTE = "flutter_route"
    private const val KEY_FLUTTER_PLAYLIST_ID = "flutter_playlist_id"
    private const val KEY_FLUTTER_PLAYBACK_STATE = "flutter_playback_state"
    private const val KEY_FLUTTER_HB_SEQ = "flutter_heartbeat_seq"
    private const val KEY_UI_VISIBILITY_STATE = "ui_visibility_state"
    private const val KEY_PRESENTATION_SESSION_ID = "presentation_session_id"
    private const val KEY_PLAYLIST_GENERATION = "playlist_generation_persisted"
    private const val KEY_CURRENT_CONTENT_ID = "current_content_id"
    private const val KEY_PLAYBACK_GENERATION = "playback_generation"
    private const val KEY_LAST_SUCCESSFUL_RENDER_MS = "last_successful_render_ms"
    private const val KEY_LAST_FOREGROUND_RESTORE_MS = "last_foreground_restore_ms"
    private const val KEY_PRESENTATION_REQUIRES_VISIBILITY = "presentation_requires_visibility"
    private const val KEY_M4_WATCHDOG_ENABLED = "m4_watchdog_enabled"
    private const val KEY_M4_SURFACE_RECOVERY = "m4_surface_recovery_enabled"
    private const val KEY_M4_OEM_PROFILE = "m4_oem_profile_enabled"
    private const val KEY_M4_VISIBILITY_ENFORCEMENT = "m4_visibility_enforcement_enabled"
    private const val KEY_M4_LAST_TICK_MS = "m4_last_watchdog_tick_ms"
    private const val KEY_M4_LAST_STAGE = "m4_last_recovery_stage"
    private const val KEY_M4_LAST_STAGE_MS = "m4_last_recovery_stage_ms"
    private const val KEY_M4_LAST_REASON = "m4_last_recovery_reason"
    private const val KEY_M4_SURFACE_RECOVERIES = "m4_surface_recovery_count"
    private const val KEY_M4_RELAUNCH_COUNT = "m4_relaunch_count"
    private const val KEY_M4_LAST_S1_MS = "m4_last_stage1_ms"
    private const val KEY_M4_LAST_S2_MS = "m4_last_stage2_ms"
    private const val KEY_M4_LAST_S3_MS = "m4_last_stage3_ms"
    private const val KEY_M4_LAST_S4_MS = "m4_last_stage4_ms"

    fun markServiceHeartbeat(context: Context) = prefs(context).edit()
        .putLong(KEY_SERVICE_HEARTBEAT_AT_MS, System.currentTimeMillis())
        .apply()

    fun markUiHeartbeat(context: Context) = prefs(context).edit()
        .putLong(KEY_UI_HEARTBEAT_AT_MS, System.currentTimeMillis())
        .apply()

    fun lastServiceHeartbeatMs(context: Context): Long =
        prefs(context).getLong(KEY_SERVICE_HEARTBEAT_AT_MS, 0L)

    fun lastUiHeartbeatMs(context: Context): Long =
        prefs(context).getLong(KEY_UI_HEARTBEAT_AT_MS, 0L)

    fun recordNativeCrash(context: Context, reason: String) {
        prefs(context).edit()
            .putLong(KEY_NATIVE_CRASH_AT_MS, System.currentTimeMillis())
            .putString(KEY_NATIVE_CRASH_REASON, reason)
            .apply()
    }

    fun lastFlutterRuntimeHeartbeatMs(context: Context): Long =
        prefs(context).getLong(KEY_FLUTTER_RUNTIME_HB_MS, 0L)

    fun lastFlutterPlayerFrameMs(context: Context): Long =
        prefs(context).getLong(KEY_FLUTTER_PLAYER_FRAME_MS, 0L)

    fun uiVisibilityState(context: Context): String =
        prefs(context).getString(KEY_UI_VISIBILITY_STATE, "unknown") ?: "unknown"

    fun presentationRequiresVisibility(context: Context): Boolean =
        prefs(context).getBoolean(KEY_PRESENTATION_REQUIRES_VISIBILITY, false)

    fun lastSuccessfulRenderMs(context: Context): Long =
        prefs(context).getLong(KEY_LAST_SUCCESSFUL_RENDER_MS, 0L)

    fun lastForegroundRestoreMs(context: Context): Long =
        prefs(context).getLong(KEY_LAST_FOREGROUND_RESTORE_MS, 0L)

    fun m4WatchdogEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_M4_WATCHDOG_ENABLED, true)

    fun m4SurfaceRecoveryEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_M4_SURFACE_RECOVERY, true)

    fun m4OemProfileEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_M4_OEM_PROFILE, true)

    fun m4VisibilityEnforcementEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_M4_VISIBILITY_ENFORCEMENT, true)

    fun setM4FeatureFlags(
        context: Context,
        watchdog: Boolean?,
        surfaceRecovery: Boolean?,
        oemProfile: Boolean?,
        visibilityEnforcement: Boolean?,
    ) {
        val e = prefs(context).edit()
        if (watchdog != null) e.putBoolean(KEY_M4_WATCHDOG_ENABLED, watchdog)
        if (surfaceRecovery != null) e.putBoolean(KEY_M4_SURFACE_RECOVERY, surfaceRecovery)
        if (oemProfile != null) e.putBoolean(KEY_M4_OEM_PROFILE, oemProfile)
        if (visibilityEnforcement != null) {
            e.putBoolean(
                KEY_M4_VISIBILITY_ENFORCEMENT,
                visibilityEnforcement,
            )
        }
        e.apply()
    }

    fun markM4WatchdogTick(context: Context) {
        prefs(context).edit().putLong(KEY_M4_LAST_TICK_MS, System.currentTimeMillis()).apply()
    }

    fun lastM4WatchdogTickMs(context: Context): Long =
        prefs(context).getLong(KEY_M4_LAST_TICK_MS, 0L)

    fun recordM4RecoveryStage(context: Context, stage: Int, reason: String) {
        prefs(context).edit()
            .putInt(KEY_M4_LAST_STAGE, stage)
            .putLong(KEY_M4_LAST_STAGE_MS, System.currentTimeMillis())
            .putString(KEY_M4_LAST_REASON, reason.take(240))
            .apply()
    }

    fun lastM4Stage(context: Context): Int = prefs(context).getInt(KEY_M4_LAST_STAGE, 0)

    fun lastM4StageMs(context: Context): Long = prefs(context).getLong(KEY_M4_LAST_STAGE_MS, 0L)

    fun lastM4Reason(context: Context): String? =
        prefs(context).getString(KEY_M4_LAST_REASON, null)

    fun incrementM4SurfaceRecoveries(context: Context) {
        val p = prefs(context)
        p.edit().putLong(KEY_M4_SURFACE_RECOVERIES, p.getLong(KEY_M4_SURFACE_RECOVERIES, 0L) + 1L).apply()
    }

    fun m4SurfaceRecoveryCount(context: Context): Long =
        prefs(context).getLong(KEY_M4_SURFACE_RECOVERIES, 0L)

    fun incrementM4RelaunchCount(context: Context) {
        val p = prefs(context)
        p.edit().putLong(KEY_M4_RELAUNCH_COUNT, p.getLong(KEY_M4_RELAUNCH_COUNT, 0L) + 1L).apply()
    }

    fun m4RelaunchCount(context: Context): Long =
        prefs(context).getLong(KEY_M4_RELAUNCH_COUNT, 0L)

    fun lastStageCooldownMs(context: Context, stage: Int): Long {
        val p = prefs(context)
        val key =
            when (stage) {
                1 -> KEY_M4_LAST_S1_MS
                2 -> KEY_M4_LAST_S2_MS
                3 -> KEY_M4_LAST_S3_MS
                4 -> KEY_M4_LAST_S4_MS
                else -> return 0L
            }
        return p.getLong(key, 0L)
    }

    fun markStageExecuted(context: Context, stage: Int) {
        val now = System.currentTimeMillis()
        val key =
            when (stage) {
                1 -> KEY_M4_LAST_S1_MS
                2 -> KEY_M4_LAST_S2_MS
                3 -> KEY_M4_LAST_S3_MS
                4 -> KEY_M4_LAST_S4_MS
                else -> return
            }
        prefs(context).edit().putLong(key, now).apply()
    }

    fun markForegroundRestore(context: Context) {
        prefs(context).edit()
            .putLong(KEY_LAST_FOREGROUND_RESTORE_MS, System.currentTimeMillis())
            .apply()
    }

    /**
     * Applies Flutter runtime heartbeat + optional session fields in one prefs transaction.
     */
    @Suppress("ComplexCondition")
    fun applyFlutterRuntimeHeartbeat(
        context: Context,
        nowMs: Long,
        route: String?,
        playlistId: String?,
        playbackState: String?,
        playerFrameMs: Long?,
        playbackEpoch: Long?,
        currentContentId: String?,
        appLifecycle: String?,
        presentationRequiresVisibility: Boolean?,
        sessionId: String?,
        playlistGeneration: Long?,
        playbackGeneration: Long?,
        lastSuccessfulRenderMs: Long?,
        uiVisibilityState: String?,
    ) {
        val p = prefs(context)
        val seq = p.getLong(KEY_FLUTTER_HB_SEQ, 0L) + 1L
        val ed = p.edit()
            .putLong(KEY_FLUTTER_RUNTIME_HB_MS, nowMs)
            .putLong(KEY_FLUTTER_HB_SEQ, seq)
        route?.let { ed.putString(KEY_FLUTTER_ROUTE, it.take(120)) }
        playlistId?.let { ed.putString(KEY_FLUTTER_PLAYLIST_ID, it.take(120)) }
        playbackState?.let { ed.putString(KEY_FLUTTER_PLAYBACK_STATE, it.take(40)) }
        if (playerFrameMs != null && playerFrameMs > 0L) {
            ed.putLong(KEY_FLUTTER_PLAYER_FRAME_MS, playerFrameMs)
        }
        if (playbackEpoch != null) ed.putLong(KEY_PLAYLIST_GENERATION, playbackEpoch)
        if (playbackGeneration != null) ed.putLong(KEY_PLAYBACK_GENERATION, playbackGeneration)
        currentContentId?.let { ed.putString(KEY_CURRENT_CONTENT_ID, it.take(120)) }
        sessionId?.let { ed.putString(KEY_PRESENTATION_SESSION_ID, it.take(64)) }
        if (presentationRequiresVisibility != null) {
            ed.putBoolean(KEY_PRESENTATION_REQUIRES_VISIBILITY, presentationRequiresVisibility)
        }
        if (lastSuccessfulRenderMs != null && lastSuccessfulRenderMs > 0L) {
            ed.putLong(KEY_LAST_SUCCESSFUL_RENDER_MS, lastSuccessfulRenderMs)
        }
        uiVisibilityState?.let { ed.putString(KEY_UI_VISIBILITY_STATE, it.take(40)) }
        appLifecycle?.let { ed.putString("flutter_app_lifecycle", it.take(24)) }
        ed.apply()
    }

    fun flutterAppLifecycle(context: Context): String =
        prefs(context).getString("flutter_app_lifecycle", "") ?: ""

    fun flutterPlaybackState(context: Context): String =
        prefs(context).getString(KEY_FLUTTER_PLAYBACK_STATE, "") ?: ""

    fun flutterHeartbeatSeq(context: Context): Long =
        prefs(context).getLong(KEY_FLUTTER_HB_SEQ, 0L)

    fun module4Snapshot(context: Context): Map<String, Any?> {
        val p = prefs(context)
        val now = System.currentTimeMillis()
        return try {
            mapOf(
                "flutterRuntimeMs" to p.getLong(KEY_FLUTTER_RUNTIME_HB_MS, 0L),
                "flutterRuntimeAgeMs" to age(now, p.getLong(KEY_FLUTTER_RUNTIME_HB_MS, 0L)),
                "flutterPlayerFrameMs" to p.getLong(KEY_FLUTTER_PLAYER_FRAME_MS, 0L),
                "flutterPlayerFrameAgeMs" to age(now, p.getLong(KEY_FLUTTER_PLAYER_FRAME_MS, 0L)),
                "flutterRoute" to p.getString(KEY_FLUTTER_ROUTE, null),
                "flutterPlaylistId" to p.getString(KEY_FLUTTER_PLAYLIST_ID, null),
                "flutterPlaybackState" to p.getString(KEY_FLUTTER_PLAYBACK_STATE, null),
                "flutterHeartbeatSeq" to p.getLong(KEY_FLUTTER_HB_SEQ, 0L),
                "flutterLifecycle" to p.getString("flutter_app_lifecycle", null),
                "uiVisibilityState" to p.getString(KEY_UI_VISIBILITY_STATE, null),
                "presentationSessionId" to p.getString(KEY_PRESENTATION_SESSION_ID, null),
                "playlistGeneration" to p.getLong(KEY_PLAYLIST_GENERATION, 0L),
                "currentContentId" to p.getString(KEY_CURRENT_CONTENT_ID, null),
                "playbackGeneration" to p.getLong(KEY_PLAYBACK_GENERATION, 0L),
                "presentationRequiresVisibility" to p.getBoolean(
                    KEY_PRESENTATION_REQUIRES_VISIBILITY,
                    false,
                ),
                "lastSuccessfulRenderMs" to p.getLong(KEY_LAST_SUCCESSFUL_RENDER_MS, 0L),
                "lastForegroundRestoreMs" to p.getLong(KEY_LAST_FOREGROUND_RESTORE_MS, 0L),
                "m4WatchdogEnabled" to p.getBoolean(KEY_M4_WATCHDOG_ENABLED, true),
                "m4SurfaceRecoveryEnabled" to p.getBoolean(KEY_M4_SURFACE_RECOVERY, true),
                "m4OemProfileEnabled" to p.getBoolean(KEY_M4_OEM_PROFILE, true),
                "m4VisibilityEnforcementEnabled" to p.getBoolean(
                    KEY_M4_VISIBILITY_ENFORCEMENT,
                    true,
                ),
                "m4LastTickMs" to p.getLong(KEY_M4_LAST_TICK_MS, 0L),
                "m4LastStage" to p.getInt(KEY_M4_LAST_STAGE, 0),
                "m4LastStageMs" to p.getLong(KEY_M4_LAST_STAGE_MS, 0L),
                "m4LastReason" to p.getString(KEY_M4_LAST_REASON, null),
                "m4SurfaceRecoveryCount" to p.getLong(KEY_M4_SURFACE_RECOVERIES, 0L),
                "m4RelaunchCount" to p.getLong(KEY_M4_RELAUNCH_COUNT, 0L),
            )
        } catch (_: Throwable) {
            emptyMap()
        }
    }

    private fun age(now: Long, ts: Long): Long? =
        if (ts <= 0L) null else (now - ts).coerceAtLeast(0L)

    private fun prefs(context: Context) = storageContext(context)
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun storageContext(context: Context): Context =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
}
