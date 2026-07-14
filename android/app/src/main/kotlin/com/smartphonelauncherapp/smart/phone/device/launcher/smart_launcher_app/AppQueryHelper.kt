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
import java.util.concurrent.Callable
import java.util.concurrent.Executors

object AppQueryHelper {

    private const val TARGET_ICON_PX = 192
    private const val ICON_CACHE_VERSION = 3
    private const val ICON_CACHE_DIR = "launcher_icon_cache"
    private const val INTERNAL_FEATURE_ACTION =
        "com.genrevibes.smartlauncher.action.INTERNAL_FEATURE"
    private const val FEATURE_CLOCK =
        "com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.ClockActivity"
    private const val FEATURE_FILE_LOCKER =
        "com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.FileLockerActivity"
    private const val FEATURE_APP_LOCKER =
        "com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AppLockerActivity"
    private const val FEATURE_APP_HIDER =
        "com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AppHiderActivity"
    private const val FEATURE_CALCULATOR =
        "com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.CalculatorVaultActivity"
    private const val FEATURE_NOTES =
        "com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.NotesVaultActivity"
    private const val FEATURE_WEATHER =
        "com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.WeatherVaultActivity"
    private const val FEATURE_BROWSER =
        "com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.BrowserVaultActivity"

    private val featureAliases = mapOf(
        FEATURE_CLOCK to "alarm_clock",
        FEATURE_FILE_LOCKER to "file_locker",
        FEATURE_APP_LOCKER to "app_locker",
        FEATURE_APP_HIDER to "app_hider",
        FEATURE_CALCULATOR to "app_hider",
        FEATURE_NOTES to "app_hider",
        FEATURE_WEATHER to "app_hider",
        FEATURE_BROWSER to "app_hider",
    )

    // Last-known display label + icon path, keyed by package. Kept fresh on
    // every app enumeration so the Install/Uninstall Assistant can title and
    // illustrate its "removed" card after PackageManager data is gone.
    private const val ASSISTANT_INDEX_PREFS = "install_assistant_index"
    private const val LEGACY_LABEL_PREFS = "install_assistant_labels"
    private const val INDEX_DELIMITER = "\u0001"

    // Process-wide cache of rasterized launcher icons. Keyed by package for
    // normal apps and component for internal aliases, valued by
    // (lastUpdateTime, bytes) so we re-rasterize only when the OS reports the
    // package has actually changed. This avoids paying Samsung's
    // LiveIconLoader / AppIconSolution cost on every drawer cold-open.
    private data class CachedIcon(val lastUpdateTime: Long, val bytes: ByteArray)
    private val iconCache = HashMap<String, CachedIcon>(256)

    // Bounded pool for parallel icon rasterization. Sized to the device's CPU
    // count (clamped) so a fresh-install enumeration of ~150 apps rasterizes
    // across cores instead of one-at-a-time on a single IO thread — the latter
    // is what made the first app list take several seconds to appear. The
    // cache lookups it fans out to are individually synchronized.
    private val rasterPool = Executors.newFixedThreadPool(
        Runtime.getRuntime().availableProcessors().coerceIn(2, 6),
    ) { r -> Thread(r, "icon-raster").apply { isDaemon = true } }

    /** Wipes every rasterized icon — the in-memory cache and the on-disk
     *  cache directory — so the next enumeration re-rasterizes from scratch.
     *  Backs the Dev View "Simulate fresh install" maintenance action. */
    fun clearAllCaches(context: Context) {
        synchronized(iconCache) { iconCache.clear() }
        val dir = iconCacheDir(context.cacheDir) ?: return
        try {
            dir.listFiles()?.forEach { it.delete() }
        } catch (_: Exception) {
            // Best effort; stale files are keyed by lastUpdateTime so a missed
            // delete is re-validated rather than served wrongly.
        }
    }

    fun invalidatePackage(pkg: String, context: Context? = null) {
        synchronized(iconCache) {
            iconCache.keys
                .filter { it == pkg || it.startsWith("$pkg/") }
                .forEach { iconCache.remove(it) }
        }
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
        val entries = queryLauncherActivities(context, includeIconSource = true)
        return buildAppMaps(context, entries, includeIconBytes)
    }

    /**
     * Single-pass "changed?" check + app list for the launcher's startup
     * refresh. Enumerates launcher activities exactly once — the previous split
     * of getLauncherSnapshotKey / hasValidLauncherIconCache / getLauncherActivities
     * walked the full PackageManager up to three times per refresh — derives the
     * snapshot key from that one pass, and only rasterizes icons when something
     * actually changed.
     */
    fun getAppsIfChanged(
        context: Context,
        knownSnapshotKey: String?,
    ): Map<String, Any?> {
        val entries = queryLauncherActivities(context, includeIconSource = true)
        val snapshotKey = computeSnapshotKey(entries)
        if (
            knownSnapshotKey != null &&
            knownSnapshotKey == snapshotKey &&
            hasValidIconCache(context.cacheDir, entries)
        ) {
            return mapOf(
                "changed" to false,
                "snapshotKey" to snapshotKey,
            )
        }
        return mapOf(
            "changed" to true,
            "snapshotKey" to snapshotKey,
            "apps" to buildAppMaps(context, entries, includeIconBytes = false),
        )
    }

    private data class IconResult(
        val entry: LauncherActivityEntry,
        val iconBytes: ByteArray?,
        val iconPath: String?,
    )

    /**
     * Rasterizes every entry's icon and packs the channel maps. Rasterization
     * is the dominant cold-start cost (load + 192px draw + PNG encode + disk
     * write per app), so it is fanned out across [rasterPool] rather than run
     * one icon at a time on the caller's single IO thread. The memory + disk
     * caches (keyed by lastUpdateTime) make a warm app a cheap lookup, so this
     * only does real work on a fresh install or after a package changes.
     */
    private fun buildAppMaps(
        context: Context,
        entries: List<LauncherActivityEntry>,
        includeIconBytes: Boolean,
    ): List<Map<String, Any?>> {
        val pm = context.packageManager
        val cacheRoot = context.cacheDir
        val tasks = entries.map { entry ->
            Callable {
                val iconBytes = getCachedOrRasterizeIcon(
                    pm,
                    entry.packageName,
                    entry.lastUpdateTime,
                    cacheRoot = cacheRoot,
                    iconCacheKey = entry.iconCacheKey,
                    iconSource = entry.iconSource,
                )
                val iconPath = iconCacheFile(cacheRoot, entry.iconCacheKey, entry.lastUpdateTime)
                    ?.takeIf { it.isFile }
                    ?.absolutePath
                IconResult(entry, iconBytes, iconPath)
            }
        }
        val results = if (tasks.isEmpty()) {
            emptyList()
        } else {
            rasterPool.invokeAll(tasks).map { it.get() }
        }

        val indexEdit = try {
            context.getSharedPreferences(ASSISTANT_INDEX_PREFS, Context.MODE_PRIVATE).edit()
        } catch (_: Exception) {
            null
        }
        val result = ArrayList<Map<String, Any?>>(results.size)
        for (r in results) {
            if (r.entry.launcherFeatureId == null) {
                indexEdit?.putString(
                    r.entry.packageName,
                    encodeAssistantIndexValue(r.entry.label, r.iconPath),
                )
            }
            result.add(
                mapOf(
                    "name" to r.entry.label,
                    "packageName" to r.entry.packageName,
                    "componentName" to r.entry.componentName,
                    "lastUpdateTime" to r.entry.lastUpdateTime,
                    "icon" to if (includeIconBytes) r.iconBytes else null,
                    "iconPath" to r.iconPath,
                    "launcherFeatureId" to r.entry.launcherFeatureId,
                )
            )
        }
        indexEdit?.apply()
        return result
    }

    private fun computeSnapshotKey(entries: List<LauncherActivityEntry>): String {
        val digest = MessageDigest.getInstance("SHA-256")
        entries
            .sortedWith(compareBy({ it.packageName }, { it.componentName }))
            .forEach { entry ->
                val value =
                    "${entry.packageName}|${entry.componentName}|${entry.lastUpdateTime}|${entry.label}\n"
                digest.update(value.toByteArray(Charsets.UTF_8))
            }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun hasValidIconCache(
        cacheRoot: File?,
        entries: List<LauncherActivityEntry>,
    ): Boolean = entries.all { entry ->
        iconCacheFile(cacheRoot, entry.iconCacheKey, entry.lastUpdateTime)?.isFile == true
    }

    private data class LauncherActivityEntry(
        val packageName: String,
        val componentName: String,
        val label: String,
        val lastUpdateTime: Long,
        val launcherFeatureId: String?,
        val iconSource: Drawable?,
    ) {
        val iconCacheKey: String
            get() = if (launcherFeatureId == null) packageName else componentName
    }

    private fun queryLauncherActivities(
        context: Context,
        includeIconSource: Boolean = false,
    ): List<LauncherActivityEntry> {
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
        // Mini-app aliases deliberately do not publish MAIN/LAUNCHER. Query
        // their app-private action separately so they remain visible here (and
        // App Hider disguises still work) without appearing in other launchers.
        val internalFeatureIntent = Intent(INTERNAL_FEATURE_ACTION).apply {
            setPackage(myPackage)
        }
        val resolveInfos = pm.queryIntentActivities(intent, flags) +
            pm.queryIntentActivities(internalFeatureIntent, flags)

        for (resolveInfo in resolveInfos) {
            val pkg = resolveInfo.activityInfo.packageName
            val activityName = resolveInfo.activityInfo.name
            val featureId = featureAliases[activityName]
            if (pkg == myPackage && featureId == null) continue
            val componentName = "$pkg/$activityName"
            // Dedupe: some OEMs (notably Samsung) expose multiple LAUNCHER
            // activities for the same package (Calendar, Clock, etc.). Keep
            // only the first — that's the one the system itself treats as the
            // primary launcher activity. Launcher feature aliases are separate
            // drawer icons even though they share this package, so dedupe them
            // by component instead.
            val dedupeKey = if (featureId == null) pkg else componentName
            if (!seen.add(dedupeKey)) continue

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

            val iconSource = if (includeIconSource && featureId != null) {
                try {
                    resolveInfo.loadIcon(pm)
                } catch (e: Exception) {
                    null
                }
            } else {
                null
            }

            result.add(
                LauncherActivityEntry(
                    packageName = pkg,
                    componentName = componentName,
                    label = label,
                    lastUpdateTime = lastUpdate,
                    launcherFeatureId = featureId,
                    iconSource = iconSource,
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
        iconCacheKey: String = pkg,
        iconSource: Drawable? = null,
    ): ByteArray? {
        synchronized(iconCache) {
            val hit = iconCache[iconCacheKey]
            if (hit != null && hit.lastUpdateTime == lastUpdateTime) {
                writeDiskIconIfMissing(cacheRoot, iconCacheKey, lastUpdateTime, hit.bytes)
                return hit.bytes
            }
        }

        val diskHit = readDiskIcon(cacheRoot, iconCacheKey, lastUpdateTime)
        if (diskHit != null) {
            synchronized(iconCache) {
                iconCache[iconCacheKey] = CachedIcon(lastUpdateTime, diskHit)
            }
            return diskHit
        }

        val bytes = try {
            (iconSource ?: pm.getApplicationIcon(pkg)).toLauncherIconBytes()
        } catch (e: Exception) {
            return null
        }
        if (bytes.isEmpty()) return null
        synchronized(iconCache) {
            iconCache[iconCacheKey] = CachedIcon(lastUpdateTime, bytes)
        }
        writeDiskIcon(cacheRoot, iconCacheKey, lastUpdateTime, bytes)
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
