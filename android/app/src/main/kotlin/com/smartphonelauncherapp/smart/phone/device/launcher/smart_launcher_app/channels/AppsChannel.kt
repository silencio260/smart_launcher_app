package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.LauncherApps
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.UserManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.xmlpull.v1.XmlPullParser
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.AppQueryHelper
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AppLockOverlay
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AppLockStore

class AppsChannel(private val activity: Activity) {

    // Dedicated background executor for the heavy getApps pass (querying the
    // package manager + rasterizing every icon). Keeps the platform thread free
    // so other channel calls and the UI thread aren't blocked while ~150 apps
    // are enumerated on cold start.
    private val ioExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "AppsChannel-io").apply { isDaemon = true }
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.genrevibes.smartlauncher/apps")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getApps" -> {
                        ioExecutor.execute {
                            try {
                                val apps = AppQueryHelper.getLauncherActivities(activity)
                                activity.runOnUiThread { result.success(apps) }
                            } catch (e: Exception) {
                                activity.runOnUiThread {
                                    result.error("GET_APPS_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    "getAppsIfChanged" -> {
                        val knownSnapshotKey = call.argument<String>("snapshotKey")
                        ioExecutor.execute {
                            try {
                                val snapshotKey = AppQueryHelper.getLauncherSnapshotKey(activity)
                                if (
                                    knownSnapshotKey != null &&
                                    knownSnapshotKey == snapshotKey &&
                                    AppQueryHelper.hasValidLauncherIconCache(activity)
                                ) {
                                    activity.runOnUiThread {
                                        result.success(
                                            mapOf(
                                                "changed" to false,
                                                "snapshotKey" to snapshotKey,
                                            )
                                        )
                                    }
                                    return@execute
                                }

                                val apps = AppQueryHelper.getLauncherActivities(activity)
                                activity.runOnUiThread {
                                    result.success(
                                        mapOf(
                                            "changed" to true,
                                            "snapshotKey" to snapshotKey,
                                            "apps" to apps,
                                        )
                                    )
                                }
                            } catch (e: Exception) {
                                activity.runOnUiThread {
                                    result.error("GET_APPS_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    "launchApp" -> {
                        val pkg = call.argument<String>("packageName")
                        if (pkg != null) {
                            val intent = activity.packageManager.getLaunchIntentForPackage(pkg)
                            if (intent != null) {
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                gateIfLocked(pkg)
                                activity.startActivity(intent)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    "launchComponent" -> {
                        val pkg = call.argument<String>("packageName")
                        val component = call.argument<String>("componentName")
                        if (pkg != null && component != null) {
                            val className = component.substringAfter('/', component)
                            val intent = Intent(Intent.ACTION_MAIN).apply {
                                addCategory(Intent.CATEGORY_LAUNCHER)
                                setComponent(ComponentName(pkg, className))
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            try {
                                gateIfLocked(pkg)
                                activity.startActivity(intent)
                                result.success(true)
                            } catch (_: Exception) {
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
                    "getIconFromPack" -> {
                        val packPackage = call.argument<String>("packPackage")
                        val componentName = call.argument<String>("componentName")
                        if (packPackage != null && componentName != null) {
                            try {
                                val bytes = getIconFromPack(packPackage, componentName)
                                result.success(bytes)
                            } catch (e: Exception) {
                                result.success(null)
                            }
                        } else {
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Instant in-launcher lock: when WE launch a locked app, draw the lock
    // overlay synchronously here (before the app window paints) so there is no
    // flash — unlike the [AppLockWatcherService] poller, which only catches
    // launches that originate outside the launcher. Needs only the overlay
    // permission; no Usage access / accessibility required for this path.
    private fun gateIfLocked(pkg: String) {
        try {
            if (AppLockStore.isConfigured(activity) &&
                AppLockStore.isLocked(activity, pkg) &&
                !AppLockStore.isUnlocked(pkg)
            ) {
                AppLockOverlay.show(activity, pkg)
            }
        } catch (_: Exception) {
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

    private fun getIconFromPack(packPackage: String, componentName: String): ByteArray? {
        val packRes = try {
            activity.packageManager.getResourcesForApplication(packPackage)
        } catch (e: PackageManager.NameNotFoundException) {
            return null
        }

        // Parse appfilter.xml to find the drawable name for this component
        val appFilterId = packRes.getIdentifier("appfilter", "xml", packPackage)
        if (appFilterId == 0) return null

        val drawableName = try {
            val xpp: XmlPullParser = packRes.getXml(appFilterId)
            var found: String? = null
            while (xpp.eventType != XmlPullParser.END_DOCUMENT) {
                if (xpp.eventType == XmlPullParser.START_TAG && xpp.name == "item") {
                    val component = xpp.getAttributeValue(null, "component") ?: ""
                    // component format: ComponentInfo{pkg/class} — match by package prefix
                    if (component.contains("{$componentName/") || component.contains("{$componentName}")) {
                        found = xpp.getAttributeValue(null, "drawable")
                        break
                    }
                }
                xpp.next()
            }
            found
        } catch (e: Exception) {
            null
        } ?: return null

        val drawableId = packRes.getIdentifier(drawableName, "drawable", packPackage)
        if (drawableId == 0) return null

        val drawable: Drawable = try {
            packRes.getDrawable(drawableId, null)
        } catch (e: Exception) {
            return null
        }

        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            drawable.bitmap
        } else {
            val w = drawable.intrinsicWidth.takeIf { it > 0 } ?: 108
            val h = drawable.intrinsicHeight.takeIf { it > 0 } ?: 108
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, w, h)
            drawable.draw(canvas)
            bmp
        }

        return ByteArrayOutputStream().also { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        }.toByteArray()
    }
}
