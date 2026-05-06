package com.example.vertisignage

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

object VertiPushCommandHandler {
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * @return true if VertiSignage consumed the message (do not forward to Flutter pipeline).
     */
    fun maybeHandleVertisignagePush(context: Context, data: Map<String, String>): Boolean {
        val cmd = data["vs_cmd"] ?: return false
        val appContext = context.applicationContext
        return when (cmd) {
            "ANNOUNCEMENT" -> {
                val payload = data["vs_payload"] ?: return false
                handleAnnouncementEnvelopeJson(appContext, payload)
            }
            "ANNOUNCEMENT_REF" -> {
                val id = data["vs_announcement_id"] ?: return false
                fetchAndShowAnnouncement(appContext, id)
            }
            "ANNOUNCEMENT_CLEAR" -> {
                CommandRelay.hideOverlay(appContext)
                // Allow Flutter to dismiss in-app layers too (native overlay already hidden).
                false
            }
            "ANNOUNCEMENT_TRANSPORT" -> false
            else -> false
        }
    }

    private fun fetchAndShowAnnouncement(context: Context, announcementId: String): Boolean {
        val (apiBase, bearer, deviceId) = PushContextStore.read(context)
        if (apiBase.isNullOrBlank() || bearer.isNullOrBlank() || deviceId.isNullOrBlank()) {
            return true
        }
        Thread {
            try {
                val url =
                    URL("$apiBase/api/devices/$deviceId/announcement-push/$announcementId")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "GET"
                conn.setRequestProperty("Authorization", "Bearer $bearer")
                conn.setRequestProperty("Accept", "application/json")
                conn.connectTimeout = 15_000
                conn.readTimeout = 15_000
                val code = conn.responseCode
                val stream =
                    if (code in 200..299) {
                        conn.inputStream
                    } else {
                        conn.errorStream ?: conn.inputStream
                    }
                val body = stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
                conn.disconnect()
                val root = JSONObject(body)
                val envelope = root.optJSONObject("data") ?: return@Thread
                maybeShowAnnouncementEnvelope(context.applicationContext, envelope)
            } catch (_: Exception) {
                /* ignore */
            }
        }.start()
        return true
    }

    private fun parseIsoUtcMillis(raw: String): Long {
        val t = raw.trim()
        if (t.isEmpty()) return 0L
        val patterns =
            arrayOf(
                "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                "yyyy-MM-dd'T'HH:mm:ss'Z'",
                "yyyy-MM-dd'T'HH:mm:ss.SSSX",
            )
        for (p in patterns) {
            try {
                val sdf =
                    SimpleDateFormat(p, Locale.US).apply {
                        timeZone = TimeZone.getTimeZone("UTC")
                    }
                val d = sdf.parse(t) ?: continue
                return d.time
            } catch (_: Exception) {
                /* try next pattern */
            }
        }
        return 0L
    }

    private fun handleAnnouncementEnvelopeJson(context: Context, json: String): Boolean {
        return try {
            val envelope = JSONObject(json)
            maybeShowAnnouncementEnvelope(context.applicationContext, envelope)
        } catch (_: Exception) {
            false
        }
    }

    private fun maybeShowAnnouncementEnvelope(context: Context, envelope: JSONObject): Boolean {
        if (envelope.optString("type") != "ANNOUNCEMENT") return false
        val payload = envelope.optJSONObject("payload") ?: return false
        val announcementId = payload.optString("announcementId").ifBlank {
            return false
        }
        val mode = payload.optString("mode", "overlay").lowercase()
        if (mode == "ticker") {
            return false
        }

        if (!PushDedupe.tryConsume(context, announcementId)) {
            return true
        }

        val title = payload.optString("title", "Announcement").ifBlank { "Announcement" }
        val durationSec = payload.optInt("durationSec", 15).coerceIn(3, 600)
        val untilDismissed = payload.optBoolean("untilDismissed", false)
        val scheduleEndsRaw = payload.optString("scheduleEndsAt").trim().ifBlank { null }
        val scheduleEndEpochMs = scheduleEndsRaw?.let { parseIsoUtcMillis(it) } ?: 0L
        val mediaUrl =
            payload.optString("mediaUrl").ifBlank {
                payload.optString("imageUrl")
            }.trim().ifBlank { null }
        val mediaKind =
            payload.optString("mediaKind").trim().ifBlank { null }

        mainHandler.post {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !Settings.canDrawOverlays(context)
            ) {
                CommandRelay.wakeApp(context)
                return@post
            }
            CommandRelay.wakeApp(context)
            CommandRelay.showOverlay(
                context = context,
                text = title,
                mediaUrl = mediaUrl,
                mediaKind = mediaKind,
                untilDismissed = untilDismissed,
                durationSec = durationSec,
                opacity = 0.9,
                scheduleEndEpochMs = scheduleEndEpochMs,
            )
        }
        return true
    }
}
