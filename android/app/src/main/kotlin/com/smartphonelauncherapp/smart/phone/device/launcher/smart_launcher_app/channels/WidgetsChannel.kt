package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Bundle
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.ByteArrayOutputStream

class WidgetsChannel(
    private val activity: Activity,
    private val appWidgetHost: AppWidgetHost,
) : PluginRegistry.ActivityResultListener {

    companion object {
        private const val CHANNEL = "com.genrevibes.smartlauncher/widgets"
        private const val REQUEST_BIND_WIDGET = 8731
    }

    private val context: Context get() = activity
    private var pendingBindResult: MethodChannel.Result? = null
    private var pendingBindId: Int = -1

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAvailableWidgets" -> getAvailableWidgets(result)
                "bindWidget" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    val providerClass = call.argument<String>("providerClass") ?: ""
                    bindWidget(packageName, providerClass, result)
                }
                "updateWidgetSize" -> {
                    val appWidgetId = call.argument<Int>("appWidgetId") ?: -1
                    val width = call.argument<Int>("width") ?: 0
                    val height = call.argument<Int>("height") ?: 0
                    updateWidgetSize(appWidgetId, width, height, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_BIND_WIDGET) return false
        val r = pendingBindResult ?: return true
        pendingBindResult = null
        if (resultCode == Activity.RESULT_OK) {
            r.success(pendingBindId)
        } else {
            appWidgetHost.deleteAppWidgetId(pendingBindId)
            r.success(-1)
        }
        pendingBindId = -1
        return true
    }

    private fun getAvailableWidgets(result: MethodChannel.Result) {
        try {
            val manager = AppWidgetManager.getInstance(context)
            val pm = context.packageManager
            val providers = manager.getInstalledProviders()

            val list = providers.mapNotNull { info ->
                try {
                    val appName = try {
                        val appInfo = pm.getApplicationInfo(info.provider.packageName, 0)
                        pm.getApplicationLabel(appInfo).toString()
                    } catch (_: PackageManager.NameNotFoundException) {
                        info.provider.packageName
                    }

                    val label = try {
                        info.loadLabel(pm) ?: info.provider.className.substringAfterLast('.')
                    } catch (_: Exception) {
                        info.provider.className.substringAfterLast('.')
                    }

                    val previewBytes: ByteArray? = try {
                        if (info.previewImage != 0) {
                            val drawable = pm.getDrawable(
                                info.provider.packageName, info.previewImage, null
                            )
                            drawable?.let { drawableToBytes(it) }
                        } else null
                    } catch (_: Exception) {
                        null
                    }

                    val appIconBytes: ByteArray? = try {
                        pm.getApplicationIcon(info.provider.packageName)?.let { drawableToBytes(it) }
                    } catch (_: Exception) {
                        null
                    }

                    val map = mutableMapOf<String, Any?>(
                        "packageName" to info.provider.packageName,
                        "providerClass" to info.provider.className,
                        "appName" to appName,
                        "label" to label,
                        "minWidth" to info.minWidth,
                        "minHeight" to info.minHeight,
                        "minResizeWidth" to info.minResizeWidth,
                        "minResizeHeight" to info.minResizeHeight,
                    )
                    if (appIconBytes != null) map["appIcon"] = appIconBytes
                    if (previewBytes != null) map["previewImage"] = previewBytes
                    map
                } catch (_: Exception) {
                    null
                }
            }

            result.success(list)
        } catch (e: Exception) {
            result.error("WIDGET_ERROR", e.message, null)
        }
    }

    private fun bindWidget(
        packageName: String,
        providerClass: String,
        result: MethodChannel.Result,
    ) {
        try {
            val appWidgetId = appWidgetHost.allocateAppWidgetId()
            val provider = ComponentName(packageName, providerClass)
            val manager = AppWidgetManager.getInstance(context)

            val bound = manager.bindAppWidgetIdIfAllowed(appWidgetId, provider)
            if (bound) {
                result.success(appWidgetId)
            } else {
                // Ask the user to grant BIND_APPWIDGET permission for this provider
                pendingBindResult = result
                pendingBindId = appWidgetId
                val intent = Intent(AppWidgetManager.ACTION_APPWIDGET_BIND).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER, provider)
                }
                activity.startActivityForResult(intent, REQUEST_BIND_WIDGET)
            }
        } catch (e: Exception) {
            result.error("BIND_ERROR", e.message, null)
        }
    }

    private fun updateWidgetSize(
        appWidgetId: Int,
        width: Int,
        height: Int,
        result: MethodChannel.Result,
    ) {
        if (appWidgetId <= 0 || width <= 0 || height <= 0) {
            result.success(false)
            return
        }

        try {
            val options = Bundle().apply {
                putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, width)
                putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, width)
                putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, height)
                putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, height)
            }
            AppWidgetManager.getInstance(context).updateAppWidgetOptions(appWidgetId, options)
            result.success(true)
        } catch (e: Exception) {
            result.error("WIDGET_RESIZE_ERROR", e.message, null)
        }
    }

    private fun drawableToBytes(drawable: Drawable): ByteArray {
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            drawable.bitmap
        } else {
            val w = drawable.intrinsicWidth.takeIf { it > 0 } ?: 120
            val h = drawable.intrinsicHeight.takeIf { it > 0 } ?: 80
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, w, h)
            drawable.draw(canvas)
            bmp
        }
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 85, stream)
        return stream.toByteArray()
    }
}
