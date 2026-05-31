package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.alarm.AlarmScheduler

/**
 * AlarmManager alarms do not survive a reboot or an app update, so we re-arm
 * every stored alarm from [AlarmScheduler.rescheduleAll]. This runs
 * independently of the launcher process / default-launcher status, so alarms
 * fire reliably after the device restarts.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            -> AlarmScheduler.rescheduleAll(context)
        }
    }
}
