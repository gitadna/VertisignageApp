package com.example.vertisignage

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

class CommandRelayReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != CommandRelay.ACTION_WAKE &&
            action != CommandRelay.ACTION_OVERLAY_SHOW &&
            action != CommandRelay.ACTION_OVERLAY_HIDE
        ) {
            return
        }

        val serviceIntent = Intent(context, CommandRelayService::class.java).apply {
            this.action = action
            putExtras(intent)
        }
        ContextCompat.startForegroundService(context, Intent(context, KioskForegroundService::class.java))
        context.startService(serviceIntent)
    }
}
