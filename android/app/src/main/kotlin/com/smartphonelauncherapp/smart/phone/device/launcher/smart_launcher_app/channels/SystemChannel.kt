package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services.LauncherAccessibilityService

class SystemChannel(private val activity: Activity) {

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.genrevibes.smartlauncher/system")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "changeWallpaper" -> {
                        try {
                            val intent = Intent(Intent.ACTION_SET_WALLPAPER)
                            activity.startActivity(Intent.createChooser(intent, "Select Wallpaper"))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("WALLPAPER_ERROR", e.message, null)
                        }
                    }
                    "expandNotifications" -> {
                        try {
                            @Suppress("DEPRECATION")
                            val sbm = activity.getSystemService("statusbar")
                            val expandClass = Class.forName("android.app.StatusBarManager")
                            val expand = expandClass.getMethod("expandNotificationsPanel")
                            expand.invoke(sbm)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "expandQuickSettings" -> {
                        try {
                            @Suppress("DEPRECATION")
                            val sbm = activity.getSystemService("statusbar")
                            val expandClass = Class.forName("android.app.StatusBarManager")
                            val expand = expandClass.getMethod("expandSettingsPanel")
                            expand.invoke(sbm)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "openAssistant" -> {
                        try {
                            val intent = Intent(Intent.ACTION_ASSIST)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            activity.startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "sleepScreen" -> {
                        val performed = LauncherAccessibilityService.performAction(
                            android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_LOCK_SCREEN
                        )
                        result.success(performed)
                    }
                    "openRecents" -> {
                        val performed = LauncherAccessibilityService.performAction(
                            android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_RECENTS
                        )
                        result.success(performed)
                    }
                    "isNotificationAccessGranted" -> {
                        result.success(isNotificationAccessGranted())
                    }
                    "isAccessibilityServiceEnabled" -> {
                        result.success(isAccessibilityServiceEnabled())
                    }
                    "requestNotificationAccess" -> {
                        activity.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(true)
                    }
                    "requestAccessibilityAccess" -> {
                        activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    "launchUrl" -> {
                        val url = call.argument<String>("url")
                        if (url != null) {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                activity.startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("LAUNCH_URL_ERROR", e.message, null)
                            }
                        } else {
                            result.error("INVALID_URL", "URL is null", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isNotificationAccessGranted(): Boolean {
        val flat = Settings.Secure.getString(
            activity.contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        val cn = ComponentName(activity, "com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services.LauncherNotificationService")
        return flat.contains(cn.flattenToString())
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val expectedService = activity.packageName + "/" +
                LauncherAccessibilityService::class.java.name
        val enabledServices = Settings.Secure.getString(
            activity.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return TextUtils.SimpleStringSplitter(':').also { it.setString(enabledServices) }
            .any { it.equals(expectedService, ignoreCase = true) }
    }
}
