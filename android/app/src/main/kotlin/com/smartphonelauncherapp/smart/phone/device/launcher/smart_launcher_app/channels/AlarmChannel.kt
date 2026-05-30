package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.app.AlarmManager
import android.content.Intent
import android.os.Build
import android.provider.AlarmClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

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
}
