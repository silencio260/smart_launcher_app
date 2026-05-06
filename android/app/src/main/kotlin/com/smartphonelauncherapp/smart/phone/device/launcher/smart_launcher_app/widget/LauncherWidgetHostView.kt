package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.widget

import android.appwidget.AppWidgetHostView
import android.content.Context
import android.view.MotionEvent

class LauncherWidgetHostView(context: Context) : AppWidgetHostView(context) {

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        // Allow widgets to receive touch events without conflicting with launcher gestures
        return false
    }
}
