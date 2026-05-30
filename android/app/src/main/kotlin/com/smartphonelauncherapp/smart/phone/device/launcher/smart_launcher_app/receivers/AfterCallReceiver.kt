package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.overlay.AfterCallOverlay

/**
 * Manifest-declared receiver for [TelephonyManager.ACTION_PHONE_STATE_CHANGED].
 *
 * It reads ONLY [TelephonyManager.EXTRA_STATE] (idle / ringing / offhook), which
 * the platform delivers without the READ_PHONE_STATE permission. It never touches
 * EXTRA_INCOMING_NUMBER or the call log, so it needs no Phone-group permission.
 *
 * When a call that was ringing or connected returns to IDLE, that's a "call ended"
 * — we raise the after-call overlay. Receiver instances are transient, so the
 * in-call flag is process-static.
 */
class AfterCallReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return
        when (intent.getStringExtra(TelephonyManager.EXTRA_STATE)) {
            TelephonyManager.EXTRA_STATE_RINGING,
            TelephonyManager.EXTRA_STATE_OFFHOOK -> wasInCall = true
            TelephonyManager.EXTRA_STATE_IDLE -> {
                if (wasInCall) {
                    wasInCall = false
                    AfterCallOverlay.show(context.applicationContext)
                }
            }
        }
    }

    private companion object {
        @Volatile
        var wasInCall = false
    }
}
