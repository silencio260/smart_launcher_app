package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.widget

import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/// Tracks the live AppWidgetHostView for each appWidgetId so other components
/// (e.g. WidgetsChannel) can snapshot the current rendered widget contents
/// without re-binding or re-creating the host.
object WidgetHostViewRegistry {
    private val views = mutableMapOf<Int, AppWidgetHostView>()

    fun register(appWidgetId: Int, view: AppWidgetHostView) {
        if (appWidgetId <= 0) return
        views[appWidgetId] = view
    }

    fun unregister(appWidgetId: Int, view: AppWidgetHostView) {
        if (views[appWidgetId] === view) views.remove(appWidgetId)
    }

    fun get(appWidgetId: Int): AppWidgetHostView? = views[appWidgetId]
}

class WidgetHostViewFactory(
    private val context: Context,
    private val appWidgetHost: AppWidgetHost,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(ctx: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val appWidgetId = (params?.get("appWidgetId") as? Int) ?: -1
        return WidgetPlatformView(context, appWidgetHost, appWidgetId)
    }
}

private class WidgetPlatformView(
    context: Context,
    appWidgetHost: AppWidgetHost,
    private val appWidgetId: Int,
) : PlatformView {

    private val hostView: AppWidgetHostView

    init {
        val info = AppWidgetManager.getInstance(context).getAppWidgetInfo(appWidgetId)
        hostView = appWidgetHost.createView(context, appWidgetId, info)
        WidgetHostViewRegistry.register(appWidgetId, hostView)
    }

    override fun getView(): View = hostView

    override fun dispose() {
        WidgetHostViewRegistry.unregister(appWidgetId, hostView)
        // Detach from parent so its Surface stops producing frames immediately.
        // Without this, the abandoned AppWidgetHostView keeps rendering into the
        // old ImageReader after Flutter has already moved on, triggering the
        // "Unable to acquire a buffer item" warning during resize.
        (hostView.parent as? android.view.ViewGroup)?.removeView(hostView)
    }
}
