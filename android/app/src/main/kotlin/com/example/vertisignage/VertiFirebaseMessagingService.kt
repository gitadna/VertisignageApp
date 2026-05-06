package com.example.vertisignage

import android.app.ActivityManager
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Parcel
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingBackgroundService
import io.flutter.plugins.firebase.messaging.FlutterFirebaseRemoteMessageLiveData
import io.flutter.plugins.firebase.messaging.FlutterFirebaseTokenLiveData

/**
 * Handles VertiSignage FCM data messages natively when the Flutter engine is not running,
 * and forwards other Firebase messages using the same pipeline as [FlutterFirebaseMessagingService].
 */
class VertiFirebaseMessagingService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        FlutterFirebaseTokenLiveData.getInstance().postToken(token)
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val data = remoteMessage.data
        if (VertiPushCommandHandler.maybeHandleVertisignagePush(applicationContext, data)) {
            return
        }

        val ctx = applicationContext
        if (isAppForeground(ctx)) {
            FlutterFirebaseRemoteMessageLiveData.getInstance().postRemoteMessage(remoteMessage)
            return
        }

        val intent = Intent(ctx, FlutterFirebaseMessagingBackgroundService::class.java)
        val parcel = Parcel.obtain()
        try {
            remoteMessage.writeToParcel(parcel, 0)
            // Matches FlutterFirebaseMessagingUtils.EXTRA_REMOTE_MESSAGE ("notification").
            intent.putExtra("notification", parcel.marshall())
        } finally {
            parcel.recycle()
        }
        FlutterFirebaseMessagingBackgroundService.enqueueMessageProcessing(
            ctx,
            intent,
            remoteMessage.originalPriority == RemoteMessage.PRIORITY_HIGH,
        )
    }

    private fun isAppForeground(context: Context): Boolean {
        val keyguard =
            context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (keyguard?.isKeyguardLocked == true) return false
        val am =
            context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            ?: return false
        val pkg = context.packageName
        return am.runningAppProcesses?.any {
            it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND &&
                it.processName == pkg
        } == true
    }
}
