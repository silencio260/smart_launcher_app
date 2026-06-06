package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.app.WallpaperManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.ByteArrayOutputStream

class WallpaperChannel(private val activity: Activity) {

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.genrevibes.smartlauncher/wallpaper")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "changeWallpaper" -> {
                        try {
                            val intent = android.content.Intent(android.content.Intent.ACTION_SET_WALLPAPER)
                            activity.startActivity(android.content.Intent.createChooser(intent, "Select Wallpaper"))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("WALLPAPER_ERROR", e.message, null)
                        }
                    }
                    "getWallpaperColors" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                            try {
                                val wm = WallpaperManager.getInstance(activity)
                                val colors = wm.getWallpaperColors(WallpaperManager.FLAG_SYSTEM)
                                if (colors != null) {
                                    result.success(listOf(
                                        colors.primaryColor.toArgb(),
                                        colors.secondaryColor?.toArgb(),
                                        colors.tertiaryColor?.toArgb(),
                                    ))
                                } else {
                                    result.success(null)
                                }
                            } catch (e: Exception) {
                                result.success(null)
                            }
                        } else {
                            result.success(null)
                        }
                    }
                    "getWallpaperBitmap" -> {
                        try {
                            val wm = WallpaperManager.getInstance(activity)
                            val drawable = wm.drawable
                            val bitmap = when (drawable) {
                                is BitmapDrawable -> drawable.bitmap
                                else -> {
                                    val b = Bitmap.createBitmap(
                                        drawable!!.intrinsicWidth.coerceAtLeast(1),
                                        drawable.intrinsicHeight.coerceAtLeast(1),
                                        Bitmap.Config.ARGB_8888
                                    )
                                    val canvas = Canvas(b)
                                    drawable.setBounds(0, 0, canvas.width, canvas.height)
                                    drawable.draw(canvas)
                                    b
                                }
                            }
                            val out = ByteArrayOutputStream()
                            bitmap.compress(Bitmap.CompressFormat.PNG, 85, out)
                            result.success(out.toByteArray())
                        } catch (e: Exception) {
                            result.error("WALLPAPER_ERROR", e.message, null)
                        }
                    }
                    "setWallpaperOffset" -> {
                        val xOffset = call.argument<Double>("xOffset") ?: 0.0
                        try {
                            val wm = WallpaperManager.getInstance(activity)
                            wm.setWallpaperOffsets(activity.window.decorView.windowToken, xOffset.toFloat(), 0f)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "setWallpaperFromFile" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_PATH", "Wallpaper path is empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(path)
                            if (!file.exists()) {
                                result.error("MISSING_FILE", "Wallpaper file does not exist", null)
                                return@setMethodCallHandler
                            }
                            val wm = WallpaperManager.getInstance(activity)
                            FileInputStream(file).use { input ->
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    wm.setStream(input, null, true, WallpaperManager.FLAG_SYSTEM)
                                } else {
                                    @Suppress("DEPRECATION")
                                    wm.setStream(input)
                                }
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("WALLPAPER_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
