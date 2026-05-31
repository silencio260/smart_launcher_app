package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.MainActivity
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.R

class ClockWidgetProvider : MiniFeatureWidgetProvider(
    title = "Clock",
    value = "Now",
    subtitle = "Tap for alarms",
    alias = "features.ClockActivity",
)

class FileLockerWidgetProvider : MiniFeatureWidgetProvider(
    title = "File Locker",
    value = "Vault",
    subtitle = "Encrypted private files",
    alias = "features.FileLockerActivity",
)

class AppLockerWidgetProvider : MiniFeatureWidgetProvider(
    title = "App Locker",
    value = "Protected",
    subtitle = "Device-wide lock status",
    alias = "features.AppLockerActivity",
)

class AppHiderWidgetProvider : MiniFeatureWidgetProvider(
    title = "App Hider",
    value = "Hidden",
    subtitle = "Open secure hidden space",
    alias = "features.AppHiderActivity",
)

open class MiniFeatureWidgetProvider(
    private val title: String,
    private val value: String,
    private val subtitle: String,
    private val alias: String,
) : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, views(context))
        }
    }

    private fun views(context: Context): RemoteViews {
        val isClock = alias.endsWith("ClockActivity")
        val layout = if (isClock) R.layout.widget_clock else R.layout.widget_feature_status
        return RemoteViews(context.packageName, layout).apply {
            if (!isClock) {
                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_value, value)
            }
            setTextViewText(R.id.widget_subtitle, subtitle)
            setOnClickPendingIntent(R.id.widget_root, pendingIntent(context))
        }
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val className = "${context.packageName}.$alias"
        val intent = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .setComponent(ComponentName(context.packageName, className))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(
            context,
            className.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
