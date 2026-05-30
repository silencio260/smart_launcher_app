package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import java.io.File
import java.security.MessageDigest

object AppQueryHelper {

    private const val TARGET_ICON_PX = 192
    private const val ICON_CACHE_VERSION = 2
    private const val ICON_CACHE_DIR = "launcher_icon_cache"

    // Last-known display label + icon path, keyed by package. Kept fresh on
    // every app enumeration so the Install/Uninstall Assistant can title and
    // illustrate its "removed" card after PackageManager data is gone.
    private const val ASSISTANT_INDEX_PREFS = "install_assistant_index"
    private const val LEGACY_LABEL_PREFS = "install_assistant_labels"
    private const val INDEX_DELIMITER = "\u0001"

    // Process-wide cache of rasterized launcher icons. Keyed by package, valued
    // by (lastUpdateTime, bytes) so we re-rasterize only when the OS reports
    // the package has actually changed. This avoids paying Samsung's
    // LiveIconLoader / AppIconSolution cost on every drawer cold-open.
    private data class CachedIcon(val lastUpdateTime: Long, val bytes: ByteArray)
    private val iconCache = HashMap<String, CachedIcon>(256)

    fun invalidatePackage(pkg: String, context: Context? = null) {
        synchronized(iconCache) { iconCache.remove(pkg) }
        context?.let { deleteDiskCacheForPackage(it, pkg) }
    }

    // Shared with WidgetsChannel so widget-picker icon loads don't re-trigger
    // Samsung's LiveIconLoader for packages the drawer already rasterized.
    fun getCachedAppIconBytes(pm: PackageManager, pkg: String): ByteArray? {
        val lastUpdate = try {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(pkg, 0).lastUpdateTime
        } catch (e: Exception) {
            0L
        }
        return getCachedOrRasterizeIcon(pm, pkg, lastUpdate)
    }

    fun getLauncherActivities(
        context: Context,
        includeIconBytes: Boolean = false,
    ): List<Map<String, Any?>> {
        val pm = context.packageManager
        val launcherApps = queryLauncherActivities(context)
        val result = ArrayList<Map<String, Any?>>(launcherApps.size)
        val indexEdit = try {
            context.getSharedPreferences(ASSISTANT_INDEX_PREFS, Context.MODE_PRIVATE).edit()
        } catch (_: Exception) {
            null
        }

        for (entry in launcherApps) {
            val pkg = entry.packageName
            val iconBytes = getCachedOrRasterizeIcon(
                pm,
                pkg,
                entry.lastUpdateTime,
                context.cacheDir,
            )
            val iconFile = iconCacheFile(
                context.cacheDir,
                pkg,
                entry.lastUpdateTime,
            )
            val iconPath = iconFile?.takeIf { it.isFile }?.absolutePath
            indexEdit?.putString(pkg, encodeAssistantIndexValue(entry.label, iconPath))

            result.add(
                mapOf(
                    "name" to entry.label,
                    "packageName" to pkg,
                    "componentName" to entry.componentName,
                    "lastUpdateTime" to entry.lastUpdateTime,
                    "icon" to if (includeIconBytes) iconBytes else null,
                    "iconPath" to iconPath,
                )
            )
        }
        indexEdit?.apply()
        return result
    }

    fun getLauncherSnapshotKey(context: Context): String {
        val digest = MessageDigest.getInstance("SHA-256")
        queryLauncherActivities(context)
            .sortedWith(compareBy({ it.packageName }, { it.componentName }))
            .forEach { entry ->
                val value = "${entry.packageName}|${entry.componentName}|${entry.lastUpdateTime}|${entry.label}\n"
                digest.update(value.toByteArray(Charsets.UTF_8))
            }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun hasValidLauncherIconCache(context: Context): Boolean =
        queryLauncherActivities(context).all { entry ->
            iconCacheFile(
                context.cacheDir,
                entry.packageName,
                entry.lastUpdateTime,
            )?.isFile == true
        }

    private data class LauncherActivityEntry(
        val packageName: String,
        val componentName: String,
        val label: String,
        val lastUpdateTime: Long,
    )

    private fun queryLauncherActivities(context: Context): List<LauncherActivityEntry> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PackageManager.MATCH_ALL
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_UNINSTALLED_PACKAGES
        }
        val myPackage = context.packageName
        val seen = HashSet<String>()
        val result = ArrayList<LauncherActivityEntry>()

        for (resolveInfo in pm.queryIntentActivities(intent, flags)) {
            val pkg = resolveInfo.activityInfo.packageName
            if (pkg == myPackage) continue
            // Dedupe: some OEMs (notably Samsung) expose multiple LAUNCHER
            // activities for the same package (Calendar, Clock, etc.). Keep
            // only the first — that's the one the system itself treats as the
            // primary launcher activity.
            if (!seen.add(pkg)) continue

            val label = try {
                resolveInfo.loadLabel(pm).toString()
            } catch (e: Exception) {
                pkg
            }

            val lastUpdate = try {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(pkg, 0).lastUpdateTime
            } catch (e: Exception) {
                0L
            }

            val activityName = resolveInfo.activityInfo.name
            result.add(
                LauncherActivityEntry(
                    packageName = pkg,
                    componentName = "$pkg/$activityName",
                    label = label,
                    lastUpdateTime = lastUpdate,
                )
            )
        }
        return result
    }

    private fun getCachedOrRasterizeIcon(
        pm: PackageManager,
        pkg: String,
        lastUpdateTime: Long,
        cacheRoot: File? = null,
    ): ByteArray? {
        synchronized(iconCache) {
            val hit = iconCache[pkg]
            if (hit != null && hit.lastUpdateTime == lastUpdateTime) {
                writeDiskIconIfMissing(cacheRoot, pkg, lastUpdateTime, hit.bytes)
                return hit.bytes
            }
        }

        val diskHit = readDiskIcon(cacheRoot, pkg, lastUpdateTime)
        if (diskHit != null) {
            synchronized(iconCache) {
                iconCache[pkg] = CachedIcon(lastUpdateTime, diskHit)
            }
            return diskHit
        }

        val bytes = try {
            pm.getApplicationIcon(pkg).toLauncherIconBytes()
        } catch (e: Exception) {
            return null
        }
        if (bytes.isEmpty()) return null
        synchronized(iconCache) {
            iconCache[pkg] = CachedIcon(lastUpdateTime, bytes)
        }
        writeDiskIcon(cacheRoot, pkg, lastUpdateTime, bytes)
        return bytes
    }

    private fun iconCacheDir(cacheRoot: File?): File? {
        if (cacheRoot == null) return null
        return File(cacheRoot, ICON_CACHE_DIR)
    }

    private fun cachePrefix(pkg: String): String =
        pkg.replace(Regex("[^A-Za-z0-9._-]"), "_")

    private fun cacheFileName(pkg: String, lastUpdateTime: Long): String =
        "${cachePrefix(pkg)}_${lastUpdateTime}_${TARGET_ICON_PX}_v${ICON_CACHE_VERSION}.png"

    private fun iconCacheFile(
        cacheRoot: File?,
        pkg: String,
        lastUpdateTime: Long,
    ): File? {
        val dir = iconCacheDir(cacheRoot) ?: return null
        return File(dir, cacheFileName(pkg, lastUpdateTime))
    }

    private fun readDiskIcon(
        cacheRoot: File?,
        pkg: String,
        lastUpdateTime: Long,
    ): ByteArray? {
        val dir = iconCacheDir(cacheRoot) ?: return null
        val file = iconCacheFile(cacheRoot, pkg, lastUpdateTime) ?: return null
        return try {
            if (!file.isFile) return null
            pruneStaleDiskIcons(dir, pkg, keepName = file.name)
            file.readBytes()
        } catch (e: Exception) {
            null
        }
    }

    private fun writeDiskIcon(
        cacheRoot: File?,
        pkg: String,
        lastUpdateTime: Long,
        bytes: ByteArray,
    ) {
        val dir = iconCacheDir(cacheRoot) ?: return
        try {
            if (!dir.exists() && !dir.mkdirs()) return
            val file = iconCacheFile(cacheRoot, pkg, lastUpdateTime) ?: return
            val tmp = File(dir, "${file.name}.tmp")
            tmp.writeBytes(bytes)
            if (file.exists()) file.delete()
            tmp.renameTo(file)
            pruneStaleDiskIcons(dir, pkg, keepName = file.name)
        } catch (e: Exception) {
            // Disk cache is an optimization only; failures must not affect app loading.
        }
    }

    private fun writeDiskIconIfMissing(
        cacheRoot: File?,
        pkg: String,
        lastUpdateTime: Long,
        bytes: ByteArray,
    ) {
        val file = iconCacheFile(cacheRoot, pkg, lastUpdateTime) ?: return
        if (file.isFile) return
        writeDiskIcon(cacheRoot, pkg, lastUpdateTime, bytes)
    }

    private fun pruneStaleDiskIcons(dir: File, pkg: String, keepName: String) {
        val prefix = "${cachePrefix(pkg)}_"
        dir.listFiles()?.forEach { file ->
            if (file.name.startsWith(prefix) && file.name != keepName) {
                file.delete()
            }
        }
    }

    private fun deleteDiskCacheForPackage(context: Context, pkg: String) {
        val dir = iconCacheDir(context.cacheDir) ?: return
        val prefix = "${cachePrefix(pkg)}_"
        try {
            dir.listFiles()?.forEach { file ->
                if (file.name.startsWith(prefix)) file.delete()
            }
        } catch (e: Exception) {
            // Ignore cache cleanup failures; stale misses are handled by lastUpdateTime.
        }
    }

    // --- last-known data for the uninstall card -------------------------------

    /** The display label last seen for [pkg], even after it's uninstalled. */
    fun lastKnownLabel(context: Context, pkg: String): String? =
        try {
            decodeAssistantIndexValue(
                context.getSharedPreferences(ASSISTANT_INDEX_PREFS, Context.MODE_PRIVATE)
                    .getString(pkg, null),
            )?.label
                ?: context.getSharedPreferences(LEGACY_LABEL_PREFS, Context.MODE_PRIVATE)
                    .getString(pkg, null)
        } catch (_: Exception) {
            null
        }

    /**
     * The most recent on-disk rasterized icon for [pkg], if one survives. Matched by
     * the package's cache-file prefix so the caller doesn't need its lastUpdateTime —
     * useful for an uninstalled package whose PackageManager entry is gone.
     */
    fun lastKnownIconFile(context: Context, pkg: String): File? {
        try {
            val indexedPath = decodeAssistantIndexValue(
                context.getSharedPreferences(ASSISTANT_INDEX_PREFS, Context.MODE_PRIVATE)
                    .getString(pkg, null),
            )?.iconPath
            if (!indexedPath.isNullOrEmpty()) {
                File(indexedPath).takeIf { it.isFile }?.let { return it }
            }
        } catch (_: Exception) {
        }

        val dir = iconCacheDir(context.cacheDir) ?: return null
        val prefix = "${cachePrefix(pkg)}_"
        return try {
            dir.listFiles()
                ?.filter { it.isFile && it.name.startsWith(prefix) && !it.name.endsWith(".tmp") }
                ?.maxByOrNull { it.lastModified() }
        } catch (_: Exception) {
            null
        }
    }

    private data class AssistantIndexEntry(val label: String, val iconPath: String?)

    private fun encodeAssistantIndexValue(label: String, iconPath: String?): String =
        "$label$INDEX_DELIMITER${iconPath.orEmpty()}"

    private fun decodeAssistantIndexValue(value: String?): AssistantIndexEntry? {
        if (value.isNullOrEmpty()) return null
        val separator = value.indexOf(INDEX_DELIMITER)
        if (separator < 0) return AssistantIndexEntry(value, null)
        return AssistantIndexEntry(
            label = value.substring(0, separator),
            iconPath = value.substring(separator + INDEX_DELIMITER.length).ifEmpty { null },
        )
    }

    private fun Drawable.toLauncherIconBytes(): ByteArray {
        val target = TARGET_ICON_PX
        val bmp = Bitmap.createBitmap(target, target, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        if (this is BitmapDrawable && this.bitmap != null) {
            val src = this.bitmap
            canvas.drawBitmap(
                src,
                null,
                android.graphics.Rect(0, 0, target, target),
                null,
            )
        } else {
            setBounds(0, 0, target, target)
            draw(canvas)
        }

        val stream = java.io.ByteArrayOutputStream(8 * 1024)
        val ok = bmp.compress(Bitmap.CompressFormat.PNG, 90, stream)
        if (!ok) stream.reset()
        bmp.recycle()
        return stream.toByteArray()
    }
}
