package com.example.vertisignage

/**
 * Maps free-form recovery reasons to stable [recovery_trigger_source] for fleet analytics.
 * Keep raw reason on each event as `legacy_reason` for debugging.
 */
object RecoveryTriggerTaxonomy {
    const val TRIGGER_BOOT = "boot"
    const val TRIGGER_WATCHDOG = "watchdog"
    const val TRIGGER_RECOVERY_WORKER = "recovery_worker"
    const val TRIGGER_SCHEDULE_POSTCHECK = "schedule_postcheck"
    const val TRIGGER_WEBSOCKET = "websocket"
    const val TRIGGER_OVERLAY = "overlay"
    const val TRIGGER_MANUAL_RESTART = "manual_restart"

    fun classify(rawReason: String): String {
        val r = rawReason.lowercase()
        return when {
            r.startsWith("boot") || r.contains(":boot") -> TRIGGER_BOOT
            r.contains("schedule_postcheck") || r.contains("postcheck") -> TRIGGER_SCHEDULE_POSTCHECK
            r.contains("watchdog_m4") || r == "watchdog" || r.contains("m4_watchdog") -> TRIGGER_WATCHDOG
            r.contains("manual_restart") -> TRIGGER_MANUAL_RESTART
            r.contains("flutter:offline_watchdog") ||
                r.contains("websocket_offline") ||
                r.contains("offline_watchdog") -> TRIGGER_WEBSOCKET
            r.contains("overlay") || (r.contains("push_fetch") && r.contains("announcement")) -> TRIGGER_OVERLAY
            r.contains("restart") && (r.contains("manual") || r.contains("user")) -> TRIGGER_MANUAL_RESTART
            r.contains("flutter:gate") ||
                r.contains("recovery_worker") ||
                r.contains("workmanager") ||
                r.contains("worker") ||
                r.contains("service_") ||
                r.contains("alarm:") ||
                r.contains("activity_post") ||
                r.contains("first_launch") ||
                r.contains("periodic:") ||
                r.contains("enqueue") -> TRIGGER_RECOVERY_WORKER
            else -> TRIGGER_RECOVERY_WORKER
        }
    }
}
