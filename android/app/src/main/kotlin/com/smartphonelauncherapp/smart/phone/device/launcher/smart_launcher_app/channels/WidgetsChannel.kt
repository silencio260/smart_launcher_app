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
import android.graphics.Rect
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import android.appwidget.AppWidgetHostView
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.widget.WidgetHostViewRegistry
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import org.xmlpull.v1.XmlPullParser
import java.io.ByteArrayOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class WidgetsChannel(
    private val activity: Activity,
    private val appWidgetHost: AppWidgetHost,
) : PluginRegistry.ActivityResultListener {

    companion object {
        private const val CHANNEL = "com.genrevibes.smartlauncher/widgets"
        private const val REQUEST_BIND_WIDGET = 8731
        private const val TAG = "WidgetSizing"
    }

    private val context: Context get() = activity
    private var pendingBindResult: MethodChannel.Result? = null
    private var pendingBindId: Int = -1

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAvailableWidgets" -> {
                    val profile = WidgetGridProfile(
                        columns = call.argument<Int>("gridColumns") ?: 5,
                        rows = call.argument<Int>("gridRows") ?: 6,
                        cellWidthDp = (call.argument<Double>("cellWidth") ?: 0.0).toFloat(),
                        cellHeightDp = (call.argument<Double>("cellHeight") ?: 0.0).toFloat(),
                        gapDp = (call.argument<Double>("gap") ?: 8.0).toFloat(),
                    )
                    android.util.Log.d(TAG, "getAvailableWidgets args=$profile")
                    getAvailableWidgets(profile, result)
                }
                "bindWidget" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    val providerClass = call.argument<String>("providerClass") ?: ""
                    bindWidget(packageName, providerClass, result)
                }
                "updateWidgetSize" -> {
                    val appWidgetId = call.argument<Int>("appWidgetId") ?: -1
                    val providerPackage = call.argument<String>("providerPackage") ?: ""
                    val providerClass = call.argument<String>("providerClass") ?: ""
                    val spanX = call.argument<Int>("spanX") ?: 0
                    val spanY = call.argument<Int>("spanY") ?: 0
                    val profile = WidgetGridProfile(
                        columns = call.argument<Int>("gridColumns") ?: 5,
                        rows = call.argument<Int>("gridRows") ?: 6,
                        cellWidthDp = (call.argument<Double>("cellWidth") ?: 0.0).toFloat(),
                        cellHeightDp = (call.argument<Double>("cellHeight") ?: 0.0).toFloat(),
                        gapDp = (call.argument<Double>("gap") ?: 8.0).toFloat(),
                    )
                    android.util.Log.d(
                        TAG,
                        "updateWidgetSize args id=$appWidgetId provider=$providerPackage/$providerClass span=${spanX}x${spanY} profile=$profile",
                    )
                    updateWidgetSize(appWidgetId, providerPackage, providerClass, spanX, spanY, profile, result)
                }
                "renderLiveWidget" -> {
                    val appWidgetId = call.argument<Int>("appWidgetId") ?: -1
                    val maxWidthPx = call.argument<Int>("maxWidthPx") ?: 0
                    val maxHeightPx = call.argument<Int>("maxHeightPx") ?: 0
                    renderLiveWidget(appWidgetId, maxWidthPx, maxHeightPx, result)
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

    private fun getAvailableWidgets(profile: WidgetGridProfile, result: MethodChannel.Result) {
        val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
        Thread {
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

                        val appIconBytes: ByteArray? = try {
                            pm.getApplicationIcon(info.provider.packageName)
                                ?.let { drawableToBytes(it, maxWidth = 120, maxHeight = 120) }
                        } catch (_: Exception) {
                            null
                        }
                        val sizing = WidgetSizing.fromProviderInfo(context, info, profile)
                        android.util.Log.d(TAG, buildString {
                            append("providerResult ")
                            append("provider=${info.provider.flattenToShortString()} ")
                            append("label=$label app=$appName ")
                            append("rawMin=${info.minWidth}x${info.minHeight} ")
                            append("rawMinResize=${info.minResizeWidth}x${info.minResizeHeight} ")
                            append("resizeMode=${info.resizeMode} ")
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                append("target=${info.targetCellWidth}x${info.targetCellHeight} ")
                                append("rawMaxResize=${info.maxResizeWidth}x${info.maxResizeHeight} ")
                            }
                            append("computedDefaultSpan=${sizing.spanX}x${sizing.spanY} ")
                            append("computedMinSpan=${sizing.minSpanX}x${sizing.minSpanY} ")
                            append("computedMaxSpan=${sizing.maxSpanX}x${sizing.maxSpanY}")
                        })
                        val (previewBytes, isGeneratedPreview) = loadWidgetPreview(info, sizing, profile, mainHandler)

                        val map = mutableMapOf<String, Any?>(
                            "packageName" to info.provider.packageName,
                            "providerClass" to info.provider.className,
                            "appName" to appName,
                            "label" to label,
                            "minWidth" to info.minWidth,
                            "minHeight" to info.minHeight,
                            "minResizeWidth" to info.minResizeWidth,
                            "minResizeHeight" to info.minResizeHeight,
                            "resizeMode" to info.resizeMode,
                            "minSpanX" to sizing.minSpanX,
                            "minSpanY" to sizing.minSpanY,
                            "spanX" to sizing.spanX,
                            "spanY" to sizing.spanY,
                            "maxSpanX" to sizing.maxSpanX,
                            "maxSpanY" to sizing.maxSpanY,
                        )
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            map["targetCellWidth"] = info.targetCellWidth
                            map["targetCellHeight"] = info.targetCellHeight
                            map["maxResizeWidth"] = info.maxResizeWidth
                            map["maxResizeHeight"] = info.maxResizeHeight
                        }
                        if (appIconBytes != null) map["appIcon"] = appIconBytes
                        if (previewBytes != null) {
                            map["previewImage"] = previewBytes
                            map["previewIsGenerated"] = isGeneratedPreview
                        }
                        map
                    } catch (_: Exception) {
                        null
                    }
                }

                val sorted = list.sortedBy { (it["appName"] as? String ?: "").lowercase() }
                mainHandler.post { result.success(sorted) }
            } catch (e: Exception) {
                mainHandler.post { result.error("WIDGET_ERROR", e.message, null) }
            }
        }.start()
    }

    private fun loadWidgetPreview(
        info: android.appwidget.AppWidgetProviderInfo,
        sizing: WidgetSizing,
        profile: WidgetGridProfile,
        mainHandler: android.os.Handler,
    ): Pair<ByteArray?, Boolean> {
        val previewLayoutBytes = renderPreviewLayoutBytes(info, sizing, profile, mainHandler)
        if (previewLayoutBytes != null) return previewLayoutBytes to true

        val drawableBytes = try {
            if (info.previewImage != 0) {
                val drawable = context.packageManager.getDrawable(
                    info.provider.packageName,
                    info.previewImage,
                    null,
                )
                drawable?.let {
                    drawableToBytes(it, maxWidth = 800, maxHeight = 533, jpeg = true)
                }
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
        return drawableBytes to (drawableBytes != null)
    }

    private fun previewLayoutUsesOnlyRemoteViewsSafeTags(
        info: android.appwidget.AppWidgetProviderInfo,
    ): Boolean {
        return try {
            val resources = context.packageManager.getResourcesForApplication(info.provider.packageName)
            val parser = resources.getXml(info.previewLayout)
            parser.use {
                var event = it.eventType
                while (event != XmlPullParser.END_DOCUMENT) {
                    if (event == XmlPullParser.START_TAG) {
                        val tagName = it.name ?: return@use false
                        val className = if (tagName == "view") {
                            it.getAttributeValue(null, "class").orEmpty()
                        } else {
                            tagName
                        }
                        if (className.contains('.') &&
                            !className.startsWith("android.view.") &&
                            !className.startsWith("android.widget.")
                        ) {
                            return@use false
                        }
                    }
                    event = it.next()
                }
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun renderPreviewLayoutBytes(
        info: android.appwidget.AppWidgetProviderInfo,
        sizing: WidgetSizing,
        profile: WidgetGridProfile,
        mainHandler: android.os.Handler,
    ): ByteArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || info.previewLayout == 0) return null
        if (!previewLayoutUsesOnlyRemoteViewsSafeTags(info)) return null

        var preview: ByteArray? = null
        val latch = CountDownLatch(1)
        mainHandler.post {
            try {
                preview = renderPreviewLayoutBytesOnMain(info, sizing, profile)
            } catch (_: Exception) {
                preview = null
            } finally {
                latch.countDown()
            }
        }
        latch.await(750, TimeUnit.MILLISECONDS)
        return preview
    }

    private fun renderPreviewLayoutBytesOnMain(
        info: android.appwidget.AppWidgetProviderInfo,
        sizing: WidgetSizing,
        profile: WidgetGridProfile,
    ): ByteArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || info.previewLayout == 0) return null

        val density = context.resources.displayMetrics.density
        val widthDp = widgetPreviewWidthDp(sizing.spanX, profile)
        val heightDp = widgetPreviewHeightDp(sizing.spanY, profile)
        val longestSide = maxOf(widthDp, heightDp).coerceAtLeast(1f)
        val previewScale = minOf(1f, 420f / longestSide)
        val widthPx = (widthDp * previewScale * density).toInt().coerceIn(96, 720)
        val heightPx = (heightDp * previewScale * density).toInt().coerceIn(64, 720)

        val hostView = AppWidgetHostView(context)
        hostView.setAppWidget(-1, info)
        hostView.updateAppWidget(RemoteViews(info.provider.packageName, info.previewLayout))
        hostView.setPadding(0, 0, 0, 0)
        hostView.measure(
            View.MeasureSpec.makeMeasureSpec(widthPx, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(heightPx, View.MeasureSpec.EXACTLY),
        )
        hostView.layout(0, 0, widthPx, heightPx)

        val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        hostView.draw(canvas)
        return bitmapToBytes(bitmap, jpeg = false)
    }

    private fun widgetPreviewWidthDp(spanX: Int, profile: WidgetGridProfile): Float {
        val cellWidth = profile.cellWidthDp.takeIf { it > 0 } ?: 72f
        val gap = profile.gapDp.takeIf { it >= 0 } ?: 8f
        return spanX.coerceAtLeast(1) * cellWidth + (spanX.coerceAtLeast(1) - 1) * gap
    }

    private fun widgetPreviewHeightDp(spanY: Int, profile: WidgetGridProfile): Float {
        val cellHeight = profile.cellHeightDp.takeIf { it > 0 } ?: 72f
        val gap = profile.gapDp.takeIf { it >= 0 } ?: 8f
        return spanY.coerceAtLeast(1) * cellHeight + (spanY.coerceAtLeast(1) - 1) * gap
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
        providerPackage: String,
        providerClass: String,
        spanX: Int,
        spanY: Int,
        profile: WidgetGridProfile,
        result: MethodChannel.Result,
    ) {
        if (appWidgetId <= 0 || spanX <= 0 || spanY <= 0) {
            result.success(false)
            return
        }

        try {
            val provider = if (providerPackage.isNotBlank() && providerClass.isNotBlank()) {
                ComponentName(providerPackage, providerClass)
            } else {
                AppWidgetManager.getInstance(context).getAppWidgetInfo(appWidgetId)?.provider
            }
            val options = WidgetSizing.sizeOptionsForWidget(context, provider, spanX, spanY, profile)
            val manager = AppWidgetManager.getInstance(context)
            android.util.Log.d(TAG, buildString {
                append("updateWidgetSize options ")
                append("id=$appWidgetId provider=${provider?.flattenToShortString()} ")
                append("span=${spanX}x${spanY} profile=$profile ")
                append("min=${options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)}x")
                append(options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT))
                append(" max=${options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH)}x")
                append(options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    append(" sizes=")
                    append(options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES))
                }
            })
            if (!WidgetSizing.sameSizeOptions(manager.getAppWidgetOptions(appWidgetId), options)) {
                manager.updateAppWidgetOptions(appWidgetId, options)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("WIDGET_RESIZE_ERROR", e.message, null)
        }
    }

    private fun renderLiveWidget(
        appWidgetId: Int,
        maxWidthPx: Int,
        maxHeightPx: Int,
        result: MethodChannel.Result,
    ) {
        if (appWidgetId <= 0) {
            result.success(null)
            return
        }
        val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
        mainHandler.post {
            try {
                result.success(snapshotWidget(appWidgetId, maxWidthPx, maxHeightPx))
            } catch (e: Exception) {
                android.util.Log.w(TAG, "renderLiveWidget id=$appWidgetId failed: ${e.message}")
                result.success(null)
            }
        }
    }

    private fun snapshotWidget(
        appWidgetId: Int,
        maxWidthPx: Int,
        maxHeightPx: Int,
    ): ByteArray? {
        val live = WidgetHostViewRegistry.get(appWidgetId)
        if (live != null && live.width > 0 && live.height > 0) {
            return drawHostView(live, live.width, live.height, maxWidthPx, maxHeightPx)
        }
        // Off-screen page: PageView never built this widget's PlatformView, so
        // we have no live host view. Build an ephemeral one via the shared
        // AppWidgetHost so it receives the latest cached RemoteViews, measure
        // it at its declared min size, and snapshot. The ephemeral takes over
        // mViews tracking until WidgetHostViewFactory creates the real view
        // when the user scrolls to that page; that's already idempotent.
        val info = AppWidgetManager.getInstance(context)
            .getAppWidgetInfo(appWidgetId) ?: return null
        val density = context.resources.displayMetrics.density
        val widthPx = info.minWidth.coerceAtLeast((120 * density).toInt())
        val heightPx = info.minHeight.coerceAtLeast((80 * density).toInt())
        val ephemeral = appWidgetHost.createView(context, appWidgetId, info)
        ephemeral.setPadding(0, 0, 0, 0)
        ephemeral.measure(
            View.MeasureSpec.makeMeasureSpec(widthPx, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(heightPx, View.MeasureSpec.EXACTLY),
        )
        ephemeral.layout(0, 0, widthPx, heightPx)
        return drawHostView(ephemeral, widthPx, heightPx, maxWidthPx, maxHeightPx)
    }

    private fun drawHostView(
        view: View,
        srcW: Int,
        srcH: Int,
        maxWidthPx: Int,
        maxHeightPx: Int,
    ): ByteArray? {
        if (srcW <= 0 || srcH <= 0) return null
        val scale = if (maxWidthPx > 0 && maxHeightPx > 0) {
            minOf(maxWidthPx.toFloat() / srcW, maxHeightPx.toFloat() / srcH, 1f)
        } else 1f
        val dstW = (srcW * scale).toInt().coerceAtLeast(1)
        val dstH = (srcH * scale).toInt().coerceAtLeast(1)
        // RGB_565 has no alpha and uses half the heap of ARGB_8888. Since we
        // paint an opaque background and encode as JPEG (also no alpha), the
        // alpha channel is wasted in ARGB_8888.
        val bitmap = Bitmap.createBitmap(dstW, dstH, Bitmap.Config.RGB_565)
        val canvas = Canvas(bitmap)
        canvas.drawColor(android.graphics.Color.BLACK)
        if (scale != 1f) canvas.scale(scale, scale)
        view.draw(canvas)
        val bytes = bitmapToBytes(bitmap, jpeg = true)
        bitmap.recycle()
        return bytes
    }

    private fun drawableToBytes(
        drawable: Drawable,
        maxWidth: Int = 512,
        maxHeight: Int = 512,
        jpeg: Boolean = false,
    ): ByteArray {
        val srcW = drawable.intrinsicWidth.takeIf { it > 0 } ?: maxWidth
        val srcH = drawable.intrinsicHeight.takeIf { it > 0 } ?: maxHeight
        val scale = minOf(maxWidth.toFloat() / srcW, maxHeight.toFloat() / srcH, 1f)
        val dstW = (srcW * scale).toInt().coerceAtLeast(1)
        val dstH = (srcH * scale).toInt().coerceAtLeast(1)

        val bmp = if (drawable is BitmapDrawable && drawable.bitmap != null && dstW == srcW && dstH == srcH && !jpeg) {
            drawable.bitmap
        } else {
            val raw = Bitmap.createBitmap(dstW, dstH, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(raw)
            if (jpeg) canvas.drawColor(android.graphics.Color.WHITE)
            drawable.setBounds(0, 0, dstW, dstH)
            drawable.draw(canvas)
            raw
        }
        val stream = ByteArrayOutputStream()
        if (jpeg) {
            bmp.compress(Bitmap.CompressFormat.JPEG, 80, stream)
        } else {
            bmp.compress(Bitmap.CompressFormat.PNG, 0, stream)
        }
        return stream.toByteArray()
    }

    private fun bitmapToBytes(bitmap: Bitmap, jpeg: Boolean = false): ByteArray {
        val stream = ByteArrayOutputStream()
        if (jpeg) {
            bitmap.compress(Bitmap.CompressFormat.JPEG, 86, stream)
        } else {
            bitmap.compress(Bitmap.CompressFormat.PNG, 0, stream)
        }
        return stream.toByteArray()
    }

    private data class WidgetSizing(
        val minSpanX: Int,
        val minSpanY: Int,
        val spanX: Int,
        val spanY: Int,
        val maxSpanX: Int,
        val maxSpanY: Int,
    ) {
        companion object {
            private const val DEFAULT_COLUMNS = 5
            private const val DEFAULT_ROWS = 6
            private const val DEFAULT_GAP_DP = 8f

            fun fromProviderInfo(
                context: Context,
                info: android.appwidget.AppWidgetProviderInfo,
                profile: WidgetGridProfile,
            ): WidgetSizing {
                val profiles = profile.supportedProfiles(context, info.provider)
                val columns = profiles.maxOf { it.columns }.coerceAtLeast(1)
                val rows = profiles.maxOf { it.rows }.coerceAtLeast(1)
                val padding = defaultPaddingDp(context, info.provider)
                // AppWidgetProviderInfo's min/max/minResize dimensions are stored in PX,
                // not dp (despite some legacy docs). Convert once up front so all span
                // math runs in dp alongside cellWidthDp/cellHeightDp.
                val density = context.resources.displayMetrics.density.takeIf { it > 0f } ?: 1f
                val minWidthDp = info.minWidth / density
                val minHeightDp = info.minHeight / density
                val minResizeWidthDp = info.minResizeWidth / density
                val minResizeHeightDp = info.minResizeHeight / density
                val maxResizeWidthDp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    info.maxResizeWidth / density
                } else 0f
                val maxResizeHeightDp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    info.maxResizeHeight / density
                } else 0f

                var resizeMinSpanX = 0
                var resizeMinSpanY = 0
                var maxSpanX = columns
                var maxSpanY = rows

                // Initial placement span uses only the current (portrait) profile so
                // the widget isn't over-inflated by a landscape profile's smaller cells.
                val placementProfile = profiles.first()
                val defaultSpanX = spanForSize(
                    padding.left + padding.right,
                    minWidthDp,
                    placementProfile.gapDp,
                    placementProfile.cellWidthDp,
                ).coerceIn(1, columns)
                val defaultSpanY = spanForSize(
                    padding.top + padding.bottom,
                    minHeightDp,
                    placementProfile.gapDp,
                    placementProfile.cellHeightDp,
                ).coerceIn(1, rows)
                android.util.Log.d(TAG, buildString {
                    append("fromProviderInfo raw ")
                    append("provider=${info.provider.flattenToShortString()} ")
                    append("grid=${columns}x${rows} ")
                    append("requestedProfile=$profile ")
                    append("resolvedProfiles=${profiles.joinToString { it.toDebugString() }} ")
                    append("placementCell=${placementProfile.cellWidthDp}x${placementProfile.cellHeightDp} ")
                    append("gap=${placementProfile.gapDp} ")
                    append("density=$density ")
                    append("rawMinPx=${info.minWidth}x${info.minHeight} ")
                    append("minDp=${minWidthDp}x${minHeightDp} ")
                    append("rawMinResizePx=${info.minResizeWidth}x${info.minResizeHeight} ")
                    append("minResizeDp=${minResizeWidthDp}x${minResizeHeightDp} ")
                    append("resizeMode=${info.resizeMode} ")
                    append("paddingDp=${padding.left}/${padding.top}/${padding.right}/${padding.bottom} ")
                    append("defaultFromMin=${defaultSpanX}x${defaultSpanY} ")
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                        append("target=${info.targetCellWidth}x${info.targetCellHeight} ")
                        append("rawMaxResizePx=${info.maxResizeWidth}x${info.maxResizeHeight} ")
                        append("maxResizeDp=${maxResizeWidthDp}x${maxResizeHeightDp}")
                    }
                })

                // Resize bounds and maxSpan still use the worst-case across all profiles
                // so the widget is constrained correctly in every orientation.
                profiles.forEach { current ->
                    resizeMinSpanX = maxOf(
                        resizeMinSpanX,
                        spanForSize(
                            padding.left + padding.right,
                            minResizeWidthDp,
                            current.gapDp,
                            current.cellWidthDp,
                        ),
                    )
                    resizeMinSpanY = maxOf(
                        resizeMinSpanY,
                        spanForSize(
                            padding.top + padding.bottom,
                            minResizeHeightDp,
                            current.gapDp,
                            current.cellHeightDp,
                        ),
                    )

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        if (info.maxResizeWidth > 0) {
                            maxSpanX = minOf(
                                maxSpanX,
                                spanForSize(
                                    padding.left + padding.right,
                                    maxResizeWidthDp,
                                    current.gapDp,
                                    current.cellWidthDp,
                                ),
                            )
                        }
                        if (info.maxResizeHeight > 0) {
                            maxSpanY = minOf(
                                maxSpanY,
                                spanForSize(
                                    padding.top + padding.bottom,
                                    maxResizeHeightDp,
                                    current.gapDp,
                                    current.cellHeightDp,
                                ),
                            )
                        }
                    }
                }

                val hasTargetSpan = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    info.targetCellWidth > 0 &&
                    info.targetCellHeight > 0
                val targetSpanX = if (hasTargetSpan) {
                    info.targetCellWidth.coerceIn(1, columns)
                } else {
                    0
                }
                val targetSpanY = if (hasTargetSpan) {
                    info.targetCellHeight.coerceIn(1, rows)
                } else {
                    0
                }

                // If minResizeWidth/Height is so large that it exceeds the grid (span > columns/rows)
                // but the widget claims to be resizable, fall back to defaultSpan (from minWidth)
                // rather than 1. This gives the widget a sensible minimum rather than allowing it
                // to collapse to a single cell. Handles widgets that set minResizeWidth >= screen
                // width in their XML (e.g. some currency converter widgets).
                val effectiveResizeMinSpanX =
                    if (resizeMinSpanX > columns && info.resizeMode and 1 != 0) defaultSpanX else resizeMinSpanX
                val effectiveResizeMinSpanY =
                    if (resizeMinSpanY > rows && info.resizeMode and 2 != 0) defaultSpanY else resizeMinSpanY
                android.util.Log.d(TAG, buildString {
                    append("resizeBounds ")
                    append("provider=${info.provider.flattenToShortString()} ")
                    append("rawResizeMinSpan=${resizeMinSpanX}x${resizeMinSpanY} ")
                    append("effectiveResizeMinSpan=${effectiveResizeMinSpanX}x${effectiveResizeMinSpanY} ")
                    append("targetSpan=${targetSpanX}x${targetSpanY} ")
                    append("maxSpanBeforeClamp=${maxSpanX}x${maxSpanY} ")
                    append("columnsRows=${columns}x${rows}")
                })

                // Use minResizeWidth/Height as the resize floor when the widget declares one.
                // If the widget is resizable but declares no minimum, allow down to 1 cell —
                // the widget's RemoteViews layout will adapt (matches One UI / Lawnchair behaviour).
                // Only fall back to defaultSpan when the widget is NOT resizable on that axis.
                // Some widgets publish inflated legacy minResize values but also publish an
                // Android 12+ target cell span. In that case, do not let the legacy minimum
                // immediately force the widget larger than its declared target.
                val minSpanX = when {
                    info.minResizeWidth > 0 && targetSpanX > 0 && info.resizeMode and 1 != 0 ->
                        minOf(effectiveResizeMinSpanX, targetSpanX)
                    info.minResizeWidth > 0 -> effectiveResizeMinSpanX
                    info.resizeMode and 1 != 0 -> 1
                    else -> defaultSpanX
                }.coerceIn(1, columns)
                val minSpanY = when {
                    info.minResizeHeight > 0 && targetSpanY > 0 && info.resizeMode and 2 != 0 ->
                        minOf(effectiveResizeMinSpanY, targetSpanY)
                    info.minResizeHeight > 0 -> effectiveResizeMinSpanY
                    info.resizeMode and 2 != 0 -> 1
                    else -> defaultSpanY
                }.coerceIn(1, rows)
                maxSpanX = maxOf(maxSpanX, minSpanX, targetSpanX).coerceIn(minSpanX, columns)
                maxSpanY = maxOf(maxSpanY, minSpanY, targetSpanY).coerceIn(minSpanY, rows)

                var spanX = defaultSpanX.coerceIn(1, columns)
                var spanY = defaultSpanY.coerceIn(1, rows)
                // Prefer the widget's declared target span (Android 12+).
                // Clamp only to the grid size — do NOT clamp against minSpanX/Y here,
                // because minSpan is a resize floor, not a placement floor. Clamping
                // against an inflated minSpan would silently override the declared target.
                // This matches Lawnchair's behavior.
                if (hasTargetSpan) {
                    spanX = targetSpanX
                    spanY = targetSpanY
                }

                android.util.Log.d(TAG, buildString {
                    append("finalSizing ")
                    append("provider=${info.provider.flattenToShortString()} ")
                    append("hasTarget=$hasTargetSpan ")
                    append("defaultFromMin=${defaultSpanX}x${defaultSpanY} ")
                    append("finalDefaultSpan=${spanX}x${spanY} ")
                    append("finalMinSpan=${minSpanX}x${minSpanY} ")
                    append("finalMaxSpan=${maxSpanX}x${maxSpanY} ")
                    append("grid=${columns}x${rows}")
                })
                return WidgetSizing(minSpanX, minSpanY, spanX, spanY, maxSpanX, maxSpanY)
            }

            fun sizeOptionsForWidget(
                context: Context,
                provider: ComponentName?,
                spanX: Int,
                spanY: Int,
                profile: WidgetGridProfile,
            ): Bundle {
                val component = provider ?: ComponentName(context.packageName, "")
                val sizes = profile.supportedProfiles(context, component).map { current ->
                    widgetSizeDp(current, spanX, spanY)
                }.distinctBy { "${it.width}x${it.height}" }
                val rect = minMaxSizes(sizes)
                android.util.Log.d(TAG, buildString {
                    append("sizeOptionsForWidget ")
                    append("provider=${component.flattenToShortString()} ")
                    append("span=${spanX}x${spanY} ")
                    append("profile=$profile ")
                    append("resolvedSizes=${sizes.joinToString { "${it.width}x${it.height}" }} ")
                    append("bounds=${rect.left}x${rect.top}-${rect.right}x${rect.bottom}")
                })
                return Bundle().apply {
                    putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, rect.left)
                    putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, rect.top)
                    putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, rect.right)
                    putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, rect.bottom)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        putParcelableArrayList(
                            AppWidgetManager.OPTION_APPWIDGET_SIZES,
                            ArrayList(sizes),
                        )
                    }
                }
            }

            fun sameSizeOptions(current: Bundle, next: Bundle): Boolean {
                val sameBounds = current.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) ==
                    next.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) &&
                    current.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT) ==
                    next.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT) &&
                    current.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH) ==
                    next.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH) &&
                    current.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT) ==
                    next.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
                if (!sameBounds || Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return sameBounds

                val currentSizes = current.getParcelableArrayList<SizeF>(
                    AppWidgetManager.OPTION_APPWIDGET_SIZES
                )
                val nextSizes = next.getParcelableArrayList<SizeF>(
                    AppWidgetManager.OPTION_APPWIDGET_SIZES
                )
                return currentSizes == nextSizes
            }

            private fun spanForSize(
                widgetPaddingDp: Int,
                widgetSizeDp: Float,
                cellSpacingDp: Float,
                cellSizeDp: Float,
            ): Int {
                if (cellSizeDp <= 0f) return 1
                val span = kotlin.math.ceil(
                    (widgetSizeDp + widgetPaddingDp + cellSpacingDp) /
                        (cellSizeDp + cellSpacingDp).toDouble(),
                ).toInt()
                return span.coerceAtLeast(1)
            }

            private fun widgetSizeDp(profile: ResolvedWidgetGridProfile, spanX: Int, spanY: Int): SizeF {
                val width = spanX * profile.cellWidthDp +
                    (spanX - 1).coerceAtLeast(0) * profile.gapDp -
                    profile.padding.left -
                    profile.padding.right
                val height = spanY * profile.cellHeightDp +
                    (spanY - 1).coerceAtLeast(0) * profile.gapDp -
                    profile.padding.top -
                    profile.padding.bottom
                return SizeF(width.coerceAtLeast(1f), height.coerceAtLeast(1f))
            }

            private fun minMaxSizes(sizes: List<SizeF>): Rect {
                if (sizes.isEmpty()) return Rect()
                var minWidth = sizes.first().width.toInt()
                var minHeight = sizes.first().height.toInt()
                var maxWidth = sizes.first().width.toInt()
                var maxHeight = sizes.first().height.toInt()
                sizes.drop(1).forEach { size ->
                    minWidth = minOf(minWidth, size.width.toInt())
                    minHeight = minOf(minHeight, size.height.toInt())
                    maxWidth = maxOf(maxWidth, size.width.toInt())
                    maxHeight = maxOf(maxHeight, size.height.toInt())
                }
                return Rect(minWidth, minHeight, maxWidth, maxHeight)
            }

            private fun defaultPaddingDp(context: Context, provider: ComponentName): Rect {
                val metrics = context.resources.displayMetrics
                val density = metrics.density.takeIf { it > 0f } ?: 1f
                val px = android.appwidget.AppWidgetHostView
                    .getDefaultPaddingForWidget(context, provider, null)
                return Rect(
                    (px.left / density).toInt(),
                    (px.top / density).toInt(),
                    (px.right / density).toInt(),
                    (px.bottom / density).toInt(),
                )
            }
        }
    }

    private data class WidgetGridProfile(
        val columns: Int,
        val rows: Int,
        val cellWidthDp: Float,
        val cellHeightDp: Float,
        val gapDp: Float,
    ) {
        fun supportedProfiles(
            context: Context,
            provider: ComponentName,
        ): List<ResolvedWidgetGridProfile> {
            val metrics = context.resources.displayMetrics
            val density = metrics.density.takeIf { it > 0f } ?: 1f
            val safeColumns = columns.coerceAtLeast(1)
            val safeRows = rows.coerceAtLeast(1)
            val safeGap = gapDp.takeIf { it > 0f } ?: 8f
            val screenWidthDp = metrics.widthPixels / density
            val screenHeightDp = metrics.heightPixels / density
            val currentCellWidth = cellWidthDp.takeIf { it > 0f }
                ?: (screenWidthDp - 16f - (safeColumns - 1) * safeGap) / safeColumns
            val currentCellHeight = cellHeightDp.takeIf { it > 0f }
                ?: (screenHeightDp * 0.62f - (safeRows - 1) * safeGap) / safeRows
            val padding = android.appwidget.AppWidgetHostView
                .getDefaultPaddingForWidget(context, provider, null)
            val paddingDp = Rect(
                (padding.left / density).toInt(),
                (padding.top / density).toInt(),
                (padding.right / density).toInt(),
                (padding.bottom / density).toInt(),
            )
            val current = ResolvedWidgetGridProfile(
                columns = safeColumns,
                rows = safeRows,
                cellWidthDp = currentCellWidth.coerceAtLeast(1f),
                cellHeightDp = currentCellHeight.coerceAtLeast(1f),
                gapDp = safeGap,
                padding = paddingDp,
            )
            val rotatedCellWidth =
                ((screenHeightDp - 16f - (safeColumns - 1) * safeGap) / safeColumns)
                    .coerceAtLeast(1f)
            val rotatedCellHeight =
                ((screenWidthDp * 0.62f - (safeRows - 1) * safeGap) / safeRows)
                    .coerceAtLeast(1f)
            val rotated = current.copy(
                cellWidthDp = rotatedCellWidth,
                cellHeightDp = rotatedCellHeight,
            )
            return if (
                kotlin.math.abs(current.cellWidthDp - rotated.cellWidthDp) < 0.5f &&
                kotlin.math.abs(current.cellHeightDp - rotated.cellHeightDp) < 0.5f
            ) {
                listOf(current)
            } else {
                listOf(current, rotated)
            }
        }
    }

    private data class ResolvedWidgetGridProfile(
        val columns: Int,
        val rows: Int,
        val cellWidthDp: Float,
        val cellHeightDp: Float,
        val gapDp: Float,
        val padding: Rect,
    ) {
        fun toDebugString(): String {
            return "${columns}x$rows cell=${cellWidthDp}x$cellHeightDp gap=$gapDp pad=${padding.left}/${padding.top}/${padding.right}/${padding.bottom}"
        }
    }
}
