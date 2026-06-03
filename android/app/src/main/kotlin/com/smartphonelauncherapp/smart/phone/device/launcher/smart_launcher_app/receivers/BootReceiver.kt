package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.alarm.AlarmScheduler
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services.AppLockWatcherService

/**
 * AlarmManager alarms do not survive a reboot or an app update, so we re-arm
 * every stored alarm from [AlarmScheduler.rescheduleAll]. We also restart the
 * App Lock watcher (BOOT_COMPLETED is exempt from the background FGS-start
 * restriction) so locked apps stay protected after a restart, with no need for
 * the launcher process or default-launcher status.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            -> {
                AlarmScheduler.rescheduleAll(context)
                AppLockWatcherService.syncFromPolicy(context)
            }
        }
    }
}
