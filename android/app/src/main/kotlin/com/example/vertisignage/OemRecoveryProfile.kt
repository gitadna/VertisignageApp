package com.example.vertisignage

import android.os.Build

/**
 * OEM-tuned spacing for Module 4 watchdog. Conservative defaults on unknown hardware.
 */
data class OemRecoveryProfile(
    val id: String,
    val healthyIntervalMs: Long,
    val presentingIntervalMs: Long,
    val urgentIntervalMs: Long,
    val stage1CooldownMs: Long,
    val stage2CooldownMs: Long,
    val stage3CooldownMs: Long,
    val stage4CooldownMs: Long,
    val flutterStalePresentingMs: Long,
    val playerFrameStaleMs: Long,
    val nativeUiStaleMs: Long,
) {
    companion object {
        private val generic =
            OemRecoveryProfile(
                id = "generic",
                healthyIntervalMs = 240_000L,
                presentingIntervalMs = 35_000L,
                urgentIntervalMs = 15_000L,
                stage1CooldownMs = 8_000L,
                stage2CooldownMs = 12_000L,
                stage3CooldownMs = 22_000L,
                stage4CooldownMs = 120_000L,
                flutterStalePresentingMs = 45_000L,
                playerFrameStaleMs = 120_000L,
                nativeUiStaleMs = 90_000L,
            )

        fun current(): OemRecoveryProfile {
            val m = (Build.MANUFACTURER ?: "").lowercase()
            val model = (Build.MODEL ?: "").lowercase()
            return when {
                m.contains("dahua") -> generic.copy(
                    id = "dahua",
                    presentingIntervalMs = 25_000L,
                    stage1CooldownMs = 6_000L,
                    flutterStalePresentingMs = 40_000L,
                )
                m.contains("hikvision") || m.contains("hik") -> generic.copy(
                    id = "hikvision",
                    presentingIntervalMs = 25_000L,
                    flutterStalePresentingMs = 40_000L,
                )
                m.contains("maxhub") -> generic.copy(id = "maxhub", presentingIntervalMs = 30_000L)
                m.contains("xiaomi") || m.contains("redmi") -> generic.copy(
                    id = "xiaomi",
                    presentingIntervalMs = 30_000L,
                    healthyIntervalMs = 300_000L,
                )
                m.contains("vivo") -> generic.copy(id = "vivo", presentingIntervalMs = 30_000L)
                m.contains("oppo") || m.contains("realme") || m.contains("oneplus") ->
                    generic.copy(id = "oppo_family", presentingIntervalMs = 30_000L)
                m.contains("tcl") -> generic.copy(id = "tcl", presentingIntervalMs = 35_000L)
                m.contains("google") && model.contains("tv") -> generic.copy(id = "android_tv", presentingIntervalMs = 35_000L)
                model.contains("tv") || m.contains("hisense") || m.contains("samsung") ->
                    generic.copy(id = "tv_like", presentingIntervalMs = 35_000L)
                else -> generic
            }
        }
    }
}
