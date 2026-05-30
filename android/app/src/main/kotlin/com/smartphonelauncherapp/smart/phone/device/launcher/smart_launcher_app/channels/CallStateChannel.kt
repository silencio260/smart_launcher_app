package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.telephony.TelephonyManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

class CallStateChannel(private val activity: Activity) {
    private var receiver: BroadcastReceiver? = null
    private var wasInCall = false

    fun register(messenger: BinaryMessenger) {
        EventChannel(messenger, "com.genrevibes.smartlauncher/call_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            if (intent?.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return
                            val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
                            when (state) {
                                TelephonyManager.EXTRA_STATE_OFFHOOK,
                                TelephonyManager.EXTRA_STATE_RINGING -> wasInCall = true
                                TelephonyManager.EXTRA_STATE_IDLE -> {
                                    if (wasInCall) {
                                        wasInCall = false
                                        activity.runOnUiThread {
                                            events.success(mapOf("eventType" to "callEnded"))
                                        }
                                    }
                                }
                            }
                        }
                    }
                    activity.registerReceiver(
                        receiver,
                        IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
                    )
                }

                override fun onCancel(arguments: Any?) {
                    receiver?.let { activity.unregisterReceiver(it) }
                    receiver = null
                    wasInCall = false
                }
            })
    }
}
