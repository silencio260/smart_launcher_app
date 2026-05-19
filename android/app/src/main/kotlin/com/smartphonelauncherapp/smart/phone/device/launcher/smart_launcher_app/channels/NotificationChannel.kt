package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.content.Intent
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services.LauncherNotificationService

class NotificationChannel(private val activity: Activity) {
    @Volatile
    private var active = false
    private var badgeCallback: Runnable? = null
    private var eventSink: EventChannel.EventSink? = null

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
                    dispose()
                    active = true
                    eventSink = events
                    val callback = Runnable {
                        activity.runOnUiThread {
                            if (!active || activity.isFinishing || activity.isDestroyed) return@runOnUiThread
                            eventSink?.success(LauncherNotificationService.badgeCounts.toMap())
                        }
                    }
                    badgeCallback = callback
                    LauncherNotificationService.onBadgeChanged = callback
                }
                override fun onCancel(arguments: Any?) {
                    dispose()
                }
            })
    }

    fun dispose() {
        active = false
        if (LauncherNotificationService.onBadgeChanged === badgeCallback) {
            LauncherNotificationService.onBadgeChanged = null
        }
        badgeCallback = null
        eventSink = null
    }
}
