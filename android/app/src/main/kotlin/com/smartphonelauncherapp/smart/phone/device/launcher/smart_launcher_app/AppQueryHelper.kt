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

    // Target launcher icon raster size (px). 192 is large enough for any drawer
    // icon at 3x DPI without leaving the GPU upload cost of a full ~432×432
    // adaptive icon on every cache miss.
    private const val TARGET_ICON_PX = 192

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
        return pm.queryIntentActivities(intent, flags)
            .filter { it.activityInfo.packageName != myPackage }
            .map { resolveInfo ->
                val pkg = resolveInfo.activityInfo.packageName
                val label = try {
                    resolveInfo.loadLabel(pm).toString()
                } catch (e: Exception) {
                    pkg
                }
                val iconBytes = try {
                    pm.getApplicationIcon(pkg).toLauncherIconBytes()
                } catch (e: Exception) {
                    null
                }
                mapOf<String, Any?>(
                    "name" to label,
                    "packageName" to pkg,
                    "icon" to iconBytes
                )
            }
    }

    private fun Drawable.toLauncherIconBytes(): ByteArray {
        val target = TARGET_ICON_PX
        // Always render into a fixed-size ARGB_8888 bitmap so the channel
        // payload stays bounded regardless of the source drawable's intrinsic
        // dimensions (adaptive icons are typically 108dp ≈ 324–432px at 3x).
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
        // WebP_LOSSY decodes ~2× faster than PNG in skia and produces ~30–60%
        // smaller payloads. Fall back to legacy WEBP on pre-R, and finally PNG
        // if a vendor implementation refuses WebP for some reason.
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
