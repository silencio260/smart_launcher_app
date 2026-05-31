package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.AlarmClock
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.receivers.SmartAlarmReceiver

class AlarmChannel(private val activity: Activity) {

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.genrevibes.smartlauncher/alarm")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNextAlarm" -> {
                        try {
                            result.success(getNextAlarm())
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }
                    "openAlarmApp" -> result.success(launchAlarmIntent(AlarmClock.ACTION_SHOW_ALARMS))
                    "createAlarm" -> result.success(launchAlarmIntent(AlarmClock.ACTION_SET_ALARM))
                    "openTimer" -> result.success(launchAlarmIntent(AlarmClock.ACTION_SET_TIMER))
                    "openStopwatch" -> result.success(launchAlarmIntent(AlarmClock.ACTION_SHOW_TIMERS))
                    "canScheduleExactAlarms" -> result.success(canScheduleExactAlarms())
                    "requestExactAlarmAccess" -> {
                        requestExactAlarmAccess()
                        result.success(true)
                    }
                    "scheduleSmartAlarm" -> {
                        val id = call.argument<String>("id")
                        val trigger = call.argument<Number>("triggerAtMillis")?.toLong()
                        val label = call.argument<String>("label") ?: "Alarm"
                        result.success(
                            if (id != null && trigger != null) {
                                scheduleSmartAlarm(id, trigger, label)
                            } else {
                                false
                            }
                        )
                    }
                    "cancelSmartAlarm" -> {
                        val id = call.argument<String>("id")
                        result.success(if (id != null) cancelSmartAlarm(id) else false)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getNextAlarm(): Map<String, Any?>? {
        val am = activity.getSystemService(AlarmManager::class.java) ?: return null
        val clock = am.nextAlarmClock ?: return null
        return mapOf(
            "triggerTime" to clock.triggerTime,
        )
    }

    private fun launchAlarmIntent(action: String): Boolean {
        return try {
            val intent = Intent(action).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (action == AlarmClock.ACTION_SET_ALARM) {
                    putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                }
                if (action == AlarmClock.ACTION_SET_TIMER) {
                    putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                }
            }
            activity.startActivity(intent)
            true
        } catch (e: Exception) {
            try {
                val fallback = activity.packageManager.getLaunchIntentForPackage("com.google.android.deskclock")
                    ?: activity.packageManager.getLaunchIntentForPackage("com.android.deskclock")
                if (fallback != null) {
                    activity.startActivity(fallback)
                    true
                } else {
                    false
                }
            } catch (e2: Exception) {
                false
            }
        }
    }

    private fun canScheduleExactAlarms(): Boolean {
        val am = activity.getSystemService(AlarmManager::class.java) ?: return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
    }

    private fun requestExactAlarmAccess() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        try {
            activity.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM))
        } catch (_: Exception) {
        }
    }

    private fun scheduleSmartAlarm(id: String, triggerAtMillis: Long, label: String): Boolean {
        val am = activity.getSystemService(AlarmManager::class.java) ?: return false
        if (!canScheduleExactAlarms()) return false
        val operation = PendingIntent.getBroadcast(
            activity,
            id.hashCode(),
            Intent(activity, SmartAlarmReceiver::class.java)
                .putExtra(SmartAlarmReceiver.EXTRA_ID, id)
                .putExtra(SmartAlarmReceiver.EXTRA_LABEL, label),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val showIntent = PendingIntent.getActivity(
            activity,
            id.hashCode() + 42,
            Intent(activity, com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AlarmRingActivity::class.java)
                .putExtra(SmartAlarmReceiver.EXTRA_ID, id)
                .putExtra(SmartAlarmReceiver.EXTRA_LABEL, label),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return try {
            am.setAlarmClock(AlarmManager.AlarmClockInfo(triggerAtMillis, showIntent), operation)
            activity.getSharedPreferences("smart_alarms", Context.MODE_PRIVATE)
                .edit()
                .putLong(id, triggerAtMillis)
                .apply()
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun cancelSmartAlarm(id: String): Boolean {
        val am = activity.getSystemService(AlarmManager::class.java) ?: return false
        val operation = PendingIntent.getBroadcast(
            activity,
            id.hashCode(),
            Intent(activity, SmartAlarmReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        if (operation != null) am.cancel(operation)
        activity.getSharedPreferences("smart_alarms", Context.MODE_PRIVATE)
            .edit()
            .remove(id)
            .apply()
        return true
    }
}
