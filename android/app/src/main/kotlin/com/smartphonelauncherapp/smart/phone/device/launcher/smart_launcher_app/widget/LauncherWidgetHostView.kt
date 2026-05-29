package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.widget

import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetProviderInfo
import android.content.Context
import android.view.MotionEvent
import android.view.View
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.WidgetsChannel

// DIAGNOSTIC: AppWidgetHost.createView() builds host views via onCreateView().
// The stock AppWidgetHost returns a plain AppWidgetHostView, so our
// LauncherWidgetHostView (and its logging) never ran. Override onCreateView so
// the host actually hands back our instrumented subclass.
class LauncherAppWidgetHost(context: Context, hostId: Int) :
    AppWidgetHost(context, hostId) {
    override fun onCreateView(
        context: Context,
        appWidgetId: Int,
        appWidget: AppWidgetProviderInfo?,
    ): AppWidgetHostView {
        val view = LauncherWidgetHostView(context, appWidgetId)
        WidgetsChannel.logJump(
            "host.onCreateView id=$appWidgetId view=${view.debugIdentity()} " +
                "provider=${appWidget?.provider?.flattenToShortString() ?: "null"}"
        )
        return view
    }
}

class LauncherWidgetHostView(
    context: Context,
    private val debugAppWidgetId: Int = -1,
) : AppWidgetHostView(context) {

    fun debugIdentity(): String =
        "${javaClass.simpleName}@${System.identityHashCode(this).toString(16)}"

    private fun locationOnScreen(): String {
        val location = IntArray(2)
        return try {
            getLocationOnScreen(location)
            "${location[0]},${location[1]}"
        } catch (_: Exception) {
            "unavailable"
        }
    }

    private fun parentName(): String =
        parent?.javaClass?.simpleName ?: "null"

    private fun childSummary(): String {
        val child = if (childCount > 0) getChildAt(0) else null
        return if (child != null) {
            "${child.javaClass.simpleName}@${System.identityHashCode(child).toString(16)}" +
                " bounds=[${child.left},${child.top},${child.right},${child.bottom}]" +
                " measured=${child.measuredWidth}x${child.measuredHeight}"
        } else {
            "none"
        }
    }

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        // Allow widgets to receive touch events without conflicting with launcher gestures
        return false
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        WidgetsChannel.logJump(
            "hostView.onAttach id=$appWidgetId debugId=$debugAppWidgetId " +
                "view=${debugIdentity()} parent=${parentName()} loc=${locationOnScreen()} " +
                "size=${width}x${height} child=${childSummary()}"
        )
    }

    override fun onDetachedFromWindow() {
        WidgetsChannel.logJump(
            "hostView.onDetach id=$appWidgetId debugId=$debugAppWidgetId " +
                "view=${debugIdentity()} parent=${parentName()} loc=${locationOnScreen()} " +
                "size=${width}x${height} child=${childSummary()}"
        )
        super.onDetachedFromWindow()
    }

    // DIAGNOSTIC: correlate with Dart "[JUMP]" prints to see whether the native
    // host (or its RemoteViews child) re-lays-out on long-press, which would
    // explain a sideways slide that the Flutter render box doesn't show.
    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
        WidgetsChannel.logJump(
            "hostView.onLayout id=$appWidgetId debugId=$debugAppWidgetId " +
                "view=${debugIdentity()} changed=$changed parent=${parentName()} " +
                "loc=${locationOnScreen()} bounds=[$l,$t,$r,$b] " +
                "size=${r - l}x${b - t} child=${childSummary()}"
        )
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        WidgetsChannel.logJump(
            "hostView.onMeasure id=$appWidgetId debugId=$debugAppWidgetId " +
                "view=${debugIdentity()} parent=${parentName()} " +
                "spec=${View.MeasureSpec.toString(widthMeasureSpec)}x${View.MeasureSpec.toString(heightMeasureSpec)} " +
                "measured=${measuredWidth}x$measuredHeight child=${childSummary()}"
        )
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        WidgetsChannel.logJump(
            "hostView.onSizeChanged id=$appWidgetId debugId=$debugAppWidgetId " +
                "view=${debugIdentity()} old=${oldw}x$oldh new=${w}x$h " +
                "loc=${locationOnScreen()} parent=${parentName()} child=${childSummary()}"
        )
    }
}
