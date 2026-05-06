package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.content.Intent
import android.content.pm.LauncherApps
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.UserManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.AppQueryHelper

class AppsChannel(private val activity: Activity) {

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.genrevibes.smartlauncher/apps")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getApps" -> {
                        try {
                            result.success(AppQueryHelper.getLauncherActivities(activity))
                        } catch (e: Exception) {
                            result.error("GET_APPS_ERROR", e.message, null)
                        }
                    }
                    "launchApp" -> {
                        val pkg = call.argument<String>("packageName")
                        if (pkg != null) {
                            val intent = activity.packageManager.getLaunchIntentForPackage(pkg)
                            if (intent != null) {
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                activity.startActivity(intent)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    "openAppSettings" -> {
                        val pkg = call.argument<String>("packageName")
                        if (pkg != null) {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                            intent.data = Uri.parse("package:$pkg")
                            activity.startActivity(intent)
                            result.success(true)
                        } else {
                            result.error("INVALID_PACKAGE", "Package name is null", null)
                        }
                    }
                    "uninstallApp" -> {
                        val pkg = call.argument<String>("packageName")
                        if (pkg != null) {
                            val intent = Intent(Intent.ACTION_DELETE)
                            intent.data = Uri.parse("package:$pkg")
                            activity.startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "getShortcuts" -> {
                        val pkg = call.argument<String>("packageName")
                        if (pkg != null) {
                            try {
                                result.success(getShortcuts(pkg))
                            } catch (e: Exception) {
                                result.success(emptyList<Map<String, Any?>>())
                            }
                        } else {
                            result.success(emptyList<Map<String, Any?>>())
                        }
                    }
                    "launchShortcut" -> {
                        val pkg = call.argument<String>("packageName") ?: return@setMethodCallHandler result.success(false)
                        val shortcutId = call.argument<String>("shortcutId") ?: return@setMethodCallHandler result.success(false)
                        try {
                            launchShortcut(pkg, shortcutId)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "getInstalledIconPacks" -> {
                        try {
                            result.success(getInstalledIconPacks())
                        } catch (e: Exception) {
                            result.success(emptyList<Map<String, Any?>>())
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getShortcuts(pkg: String): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return emptyList()
        val sm = activity.getSystemService(android.content.pm.ShortcutManager::class.java)
            ?: return emptyList()
        // Only dynamic + manifest shortcuts visible to launcher
        return try {
            val launcherApps = activity.getSystemService(LauncherApps::class.java) ?: return emptyList()
            val userManager = activity.getSystemService(UserManager::class.java) ?: return emptyList()
            val query = LauncherApps.ShortcutQuery()
                .setQueryFlags(
                    LauncherApps.ShortcutQuery.FLAG_MATCH_DYNAMIC or
                    LauncherApps.ShortcutQuery.FLAG_MATCH_MANIFEST
                )
                .setPackage(pkg)
            val shortcuts = launcherApps.getShortcuts(query, userManager.userProfiles[0]) ?: emptyList()
            shortcuts.map { s ->
                mapOf(
                    "id" to s.id,
                    "packageName" to s.`package`,
                    "shortLabel" to s.shortLabel?.toString(),
                    "longLabel" to s.longLabel?.toString(),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun launchShortcut(pkg: String, shortcutId: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return
        val launcherApps = activity.getSystemService(LauncherApps::class.java) ?: return
        val userManager = activity.getSystemService(UserManager::class.java) ?: return
        launcherApps.startShortcut(pkg, shortcutId, null, null, userManager.userProfiles[0])
    }

    private fun getInstalledIconPacks(): List<Map<String, Any?>> {
        val pm = activity.packageManager
        val intent = Intent("org.adw.ActivityStarter.THEMES")
        val resolveInfos = pm.queryIntentActivities(intent, PackageManager.GET_META_DATA)
        return resolveInfos.map { info ->
            mapOf(
                "packageName" to info.activityInfo.packageName,
                "label" to info.loadLabel(pm).toString(),
            )
        }
    }
}
