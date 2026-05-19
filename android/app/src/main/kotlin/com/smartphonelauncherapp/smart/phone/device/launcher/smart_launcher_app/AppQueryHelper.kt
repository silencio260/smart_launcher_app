package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build

object AppQueryHelper {

    private const val TARGET_ICON_PX = 192

    // Process-wide cache of rasterized launcher icons. Keyed by package, valued
    // by (lastUpdateTime, bytes) so we re-rasterize only when the OS reports
    // the package has actually changed. This avoids paying Samsung's
    // LiveIconLoader / AppIconSolution cost on every drawer cold-open.
    private data class CachedIcon(val lastUpdateTime: Long, val bytes: ByteArray)
    private val iconCache = HashMap<String, CachedIcon>(256)

    fun invalidatePackage(pkg: String) {
        synchronized(iconCache) { iconCache.remove(pkg) }
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

    fun getLauncherActivities(context: Context): List<Map<String, Any?>> {
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
        val result = ArrayList<Map<String, Any?>>()

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

            val iconBytes = getCachedOrRasterizeIcon(pm, pkg, lastUpdate)

            result.add(
                mapOf(
                    "name" to label,
                    "packageName" to pkg,
                    "icon" to iconBytes,
                )
            )
        }
        return result
    }

    private fun getCachedOrRasterizeIcon(
        pm: PackageManager,
        pkg: String,
        lastUpdateTime: Long,
    ): ByteArray? {
        synchronized(iconCache) {
            val hit = iconCache[pkg]
            if (hit != null && hit.lastUpdateTime == lastUpdateTime) {
                return hit.bytes
            }
        }
        val bytes = try {
            pm.getApplicationIcon(pkg).toLauncherIconBytes()
        } catch (e: Exception) {
            return null
        }
        synchronized(iconCache) {
            iconCache[pkg] = CachedIcon(lastUpdateTime, bytes)
        }
        return bytes
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
        val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            bmp.compress(Bitmap.CompressFormat.WEBP_LOSSY, 88, stream)
        } else {
            @Suppress("DEPRECATION")
            bmp.compress(Bitmap.CompressFormat.WEBP, 88, stream)
        }
        if (!ok) {
            stream.reset()
            bmp.compress(Bitmap.CompressFormat.PNG, 90, stream)
        }
        bmp.recycle()
        return stream.toByteArray()
    }
}
