package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.app.AlarmManager
import android.os.Build
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
}
