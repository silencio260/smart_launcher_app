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
                    pm.getApplicationIcon(pkg).toBytes()
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

    private fun Drawable.toBytes(): ByteArray {
        val bitmap = if (this is BitmapDrawable) {
            this.bitmap
        } else {
            val w = intrinsicWidth.coerceAtLeast(1)
            val h = intrinsicHeight.coerceAtLeast(1)
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            setBounds(0, 0, canvas.width, canvas.height)
            draw(canvas)
            bmp
        }
        val stream = java.io.ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 85, stream)
        return stream.toByteArray()
    }
}
