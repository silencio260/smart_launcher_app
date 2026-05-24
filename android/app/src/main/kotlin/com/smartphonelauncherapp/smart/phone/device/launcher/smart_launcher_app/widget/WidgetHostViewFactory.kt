package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.widget

import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/// Tracks live AppWidgetHostViews and pools detached ones for reuse.
///
/// Two maps:
/// - [views]: currently-mounted hosts, so WidgetsChannel can snapshot the
///   live rendered widget contents without re-binding.
/// - [pool]: detached but still-alive hosts, keyed by appWidgetId. When a
///   PlatformView for the same id is created again (e.g. uncovering the
///   home screen after returning from Settings), we hand back the cached
///   AppWidgetHostView instead of paying the ~150ms cost of
///   `appWidgetHost.createView` — that call binders to system_server for
///   `getAppWidgetInfo`, allocates a new view, and triggers
///   CustomFrequencyManager setup per platform view host.
object WidgetHostViewRegistry {
    private val views = mutableMapOf<Int, AppWidgetHostView>()
    private val pool = mutableMapOf<Int, AppWidgetHostView>()

    fun register(appWidgetId: Int, view: AppWidgetHostView) {
        if (appWidgetId <= 0) return
        views[appWidgetId] = view
    }

    fun unregister(appWidgetId: Int, view: AppWidgetHostView) {
        if (views[appWidgetId] === view) views.remove(appWidgetId)
    }

    fun get(appWidgetId: Int): AppWidgetHostView? = views[appWidgetId]

    /// Park a detached AppWidgetHostView for the same appWidgetId to reuse.
    fun pool(appWidgetId: Int, view: AppWidgetHostView) {
        if (appWidgetId <= 0) return
        pool[appWidgetId] = view
    }

    /// Take the cached AppWidgetHostView for an id (caller takes ownership).
    fun acquire(appWidgetId: Int): AppWidgetHostView? = pool.remove(appWidgetId)

    /// Drop all pooled views. Call on activity destroy — pooled hosts hold
    /// a context reference and would leak across activity recreations.
    fun clearPool() {
        pool.clear()
    }
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
        val cached = WidgetHostViewRegistry.acquire(appWidgetId)
        hostView = cached ?: run {
            val info = AppWidgetManager.getInstance(context).getAppWidgetInfo(appWidgetId)
            appWidgetHost.createView(context, appWidgetId, info)
        }
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
        // Park for reuse next time the same id is mounted. AppWidgetHost keeps
        // pushing RemoteViews updates into this view while it sits detached,
        // so when we re-attach it, the displayed contents are already current.
        WidgetHostViewRegistry.pool(appWidgetId, hostView)
    }
}
