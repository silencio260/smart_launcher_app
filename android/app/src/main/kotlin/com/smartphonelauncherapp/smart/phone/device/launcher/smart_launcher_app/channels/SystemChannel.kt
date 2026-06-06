package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.app.AppOpsManager
import android.os.BatteryManager
import android.app.role.RoleManager
import android.content.Context
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services.AppLockWatcherService
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services.LauncherAccessibilityService

class SystemChannel(private val activity: Activity) {

    companion object {
        private const val REQUEST_CODE_HOME_ROLE = 4011
        private const val APP_LOCK_PREFS = "app_lock_policy"
        private const val KEY_LOCKED_PACKAGES = "locked_packages"

        @Volatile
        private var pendingFeatureRoute: String? = null

        fun deliverFeatureRoute(route: String) {
            pendingFeatureRoute = route
        }
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
                    "getBatteryLevel" -> {
                        try {
                            val bm = activity.getSystemService(BatteryManager::class.java)
                            val level = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
                            result.success(level)
                        } catch (e: Exception) {
                            result.success(-1)
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
                        openAccessibilitySettings()
                        result.success(true)
                    }
                    "consumePendingFeatureRoute" -> {
                        val route = pendingFeatureRoute
                        pendingFeatureRoute = null
                        result.success(route)
                    }
                    "setDeviceLockedApps" -> {
                        val packageNames =
                            call.argument<List<String>>("packageNames") ?: emptyList()
                        activity.getSharedPreferences(APP_LOCK_PREFS, Context.MODE_PRIVATE)
                            .edit()
                            .putStringSet(KEY_LOCKED_PACKAGES, packageNames.toSet())
                            .apply()
                        AppLockWatcherService.syncFromPolicy(activity)
                        result.success(true)
                    }
                    "syncAppLockWatcher" -> {
                        AppLockWatcherService.syncFromPolicy(activity)
                        result.success(true)
                    }
                    "isUsageAccessEnabled" -> {
                        result.success(isUsageAccessEnabled())
                    }
                    "requestUsageAccess" -> {
                        try {
                            activity.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "setAppHiderDisguise" -> {
                        val label = call.argument<String>("label") ?: "App Hider"
                        setAppHiderDisguise(label)
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
                    "openSettingsAction" -> {
                        val action = call.argument<String>("action")
                        result.success(openSettingsAction(action))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Opens a system Settings screen by its android.provider.Settings action
    // string (e.g. ACTION_WIFI_SETTINGS). Falls back to the top-level Settings
    // app if the specific action can't be resolved on this device.
    private fun openSettingsAction(action: String?): Boolean {
        return try {
            val resolved = if (action.isNullOrEmpty()) Settings.ACTION_SETTINGS else action
            var intent = Intent(resolved).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (intent.resolveActivity(activity.packageManager) == null) {
                intent = Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
            true
        } catch (e: Exception) {
            false
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

    // Deep-links straight to OUR accessibility service's on/off page (the
    // "Smart Launcher Accessibility" toggle) instead of the long generic list,
    // which buries the service several taps deep on One UI. Falls back to the
    // generic Accessibility settings if the OEM rejects the deep-link.
    private fun openAccessibilitySettings() {
        val component = ComponentName(
            activity,
            LauncherAccessibilityService::class.java
        ).flattenToString()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val args = Bundle().apply {
                    putString(":settings:fragment_args_key", component)
                }
                // Use the literal action string rather than the SDK constant
                // (Settings.ACTION_ACCESSIBILITY_DETAILS_SETTINGS) so this compiles
                // regardless of compileSdk; the value is stable across versions.
                val intent = Intent("android.settings.ACCESSIBILITY_DETAILS_SETTINGS").apply {
                    putExtra(":settings:fragment_args_key", component)
                    putExtra(":settings:show_fragment_args", args)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                activity.startActivity(intent)
                return
            } catch (e: Exception) {
                // Fall through to the generic accessibility list below.
            }
        }
        try {
            activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        } catch (e: Exception) {
            // Nothing else we can do; the Dart side re-checks on resume.
        }
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

    private fun isUsageAccessEnabled(): Boolean {
        val appOps = activity.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                activity.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                activity.packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun setAppHiderDisguise(label: String) {
        val pm = activity.packageManager
        val aliases = mapOf(
            "App Hider" to "features.AppHiderActivity",
            "Calculator" to "features.CalculatorVaultActivity",
            "Notes" to "features.NotesVaultActivity",
            "Weather" to "features.WeatherVaultActivity",
            "Browser" to "features.BrowserVaultActivity",
        )
        val selected = aliases[label] ?: aliases.getValue("App Hider")
        for ((_, alias) in aliases) {
            val state = if (alias == selected) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            pm.setComponentEnabledSetting(
                ComponentName(activity.packageName, "${activity.packageName}.$alias"),
                state,
                PackageManager.DONT_KILL_APP,
            )
        }
    }
}
