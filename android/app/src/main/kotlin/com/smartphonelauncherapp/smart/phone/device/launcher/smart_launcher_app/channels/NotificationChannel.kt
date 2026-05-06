package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.content.Intent
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services.LauncherNotificationService

class NotificationChannel(private val activity: Activity) {

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.genrevibes.smartlauncher/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBadgeCounts" -> {
                        result.success(LauncherNotificationService.badgeCounts.toMap())
                    }
                    "requestNotificationAccess" -> {
                        activity.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(messenger, "com.genrevibes.smartlauncher/notifications/badge_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    LauncherNotificationService.onBadgeChanged = Runnable {
                        activity.runOnUiThread {
                            events.success(LauncherNotificationService.badgeCounts.toMap())
                        }
                    }
                }
                override fun onCancel(arguments: Any?) {
                    LauncherNotificationService.onBadgeChanged = null
                }
            })
    }
}
