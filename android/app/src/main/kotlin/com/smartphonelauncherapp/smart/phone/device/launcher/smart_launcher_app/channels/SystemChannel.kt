package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services.LauncherAccessibilityService

class SystemChannel(private val activity: Activity) {

    companion object {
        private const val REQUEST_CODE_HOME_ROLE = 4011
    }

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
                    "canDrawOverlays" -> {
                        result.success(
                            Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                                Settings.canDrawOverlays(activity)
                        )
                    }
                    "requestOverlayPermission" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                val intent = Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:${activity.packageName}")
                                )
                                activity.startActivity(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "isDefaultLauncher" -> {
                        result.success(isDefaultLauncher())
                    }
                    "requestHomeRole" -> {
                        result.success(requestHomeRole())
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

    private fun isDefaultLauncher(): Boolean {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolved = activity.packageManager.resolveActivity(
            intent,
            PackageManager.MATCH_DEFAULT_ONLY
        )
        return resolved?.activityInfo?.packageName == activity.packageName
    }

    // Prompts the user to make this app the default home launcher. On Android 10+
    // this uses RoleManager.ROLE_HOME (a single system dialog); on older versions
    // (or if the role is unavailable / already held) it opens Home settings so the
    // user can pick a launcher manually. Returns false only if nothing could be
    // launched. The Dart side re-checks isDefaultLauncher on resume.
    private fun requestHomeRole(): Boolean {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roleManager = activity.getSystemService(RoleManager::class.java)
                if (roleManager != null &&
                    roleManager.isRoleAvailable(RoleManager.ROLE_HOME) &&
                    !roleManager.isRoleHeld(RoleManager.ROLE_HOME)
                ) {
                    val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_HOME)
                    activity.startActivityForResult(intent, REQUEST_CODE_HOME_ROLE)
                    return true
                }
            }
            activity.startActivity(Intent(Settings.ACTION_HOME_SETTINGS))
            return true
        } catch (e: Exception) {
            return try {
                activity.startActivity(Intent(Settings.ACTION_HOME_SETTINGS))
                true
            } catch (e2: Exception) {
                false
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
