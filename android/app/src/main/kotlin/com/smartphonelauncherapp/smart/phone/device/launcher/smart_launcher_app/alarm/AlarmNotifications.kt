package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AlarmRingActivity
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services.AlarmRingService

/**
 * High-importance, full-screen-intent notification used to launch the ringing
 * UI even from the background / over the lockscreen on Android 10+ (where a
 * plain `startActivity` from a receiver is blocked). The notification is the
 * foreground notification for [AlarmRingService].
 */
object AlarmNotifications {
    const val CHANNEL_ID = "smart_alarm_ring"
    const val RING_NOTIFICATION_ID = 49281

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Alarms & timers",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Ringing alarms and timers"
            setSound(null, null) // Sound is played by AlarmRingService on the alarm stream.
            enableVibration(false)
            setBypassDnd(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(channel)
    }

    fun buildRingNotification(context: Context, spec: AlarmSpec): Notification {
        ensureChannel(context)
        val isTimer = spec.kind == "timer"

        val fullScreen = PendingIntent.getActivity(
            context,
            AlarmScheduler.requestCode(spec.id) + 2,
            AlarmRingActivity.ringIntent(context, spec.id, spec.label, spec.kind),
            piFlags(),
        )

        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            Notification.Builder(context).setPriority(Notification.PRIORITY_MAX)
        }

        builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(if (isTimer) "Timer" else spec.label)
            .setContentText(if (isTimer) spec.label else "Alarm")
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(fullScreen)
            .setFullScreenIntent(fullScreen, true)
            .addAction(0, "Dismiss", servicePendingIntent(context, spec, AlarmRingService.ACTION_DISMISS, 100))

        if (!isTimer) {
            builder.addAction(
                0,
                "Snooze",
                servicePendingIntent(context, spec, AlarmRingService.ACTION_SNOOZE, 101),
            )
        }
        return builder.build()
    }

    fun cancel(context: Context) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(RING_NOTIFICATION_ID)
    }

    private fun servicePendingIntent(
        context: Context,
        spec: AlarmSpec,
        action: String,
        codeOffset: Int,
    ): PendingIntent {
        val intent = Intent(context, AlarmRingService::class.java)
            .setAction(action)
            .putExtra(AlarmRingService.EXTRA_ID, spec.id)
            .putExtra(AlarmRingService.EXTRA_SPEC, spec.toJson().toString())
        val code = AlarmScheduler.requestCode(spec.id) + codeOffset
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(context, code, intent, piFlags())
        } else {
            PendingIntent.getService(context, code, intent, piFlags())
        }
    }

    private fun piFlags(): Int =
        PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
}
