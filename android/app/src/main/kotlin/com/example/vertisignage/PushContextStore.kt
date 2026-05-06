package com.example.vertisignage

import android.content.Context

/** Persisted REST context so native FCM can GET announcement payloads when the Flutter VM is dead. */
object PushContextStore {
    private const val PREFS = "vertisignage_push_context"
    private const val KEY_API = "api_base_url"
    private const val KEY_TOKEN = "access_token"
    private const val KEY_DEVICE = "device_id"

    fun sync(context: Context, apiBaseUrl: String?, accessToken: String?, deviceId: String?) {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit().apply {
            putString(
                KEY_API,
                apiBaseUrl?.trim()?.trimEnd('/')?.takeIf { it.isNotEmpty() },
            )
            putString(KEY_TOKEN, accessToken?.takeIf { it.isNotEmpty() })
            putString(KEY_DEVICE, deviceId?.takeIf { it.isNotEmpty() })
            apply()
        }
    }

    fun read(context: Context): Triple<String?, String?, String?> {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return Triple(
            prefs.getString(KEY_API, null),
            prefs.getString(KEY_TOKEN, null),
            prefs.getString(KEY_DEVICE, null),
        )
    }
}
