package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        // Flutter/Hive owns the durable alarm model. The native mirror is kept
        // only so scheduled alarms can be cancelled by id; Dart reschedules
        // enabled alarms when the launcher process starts after boot.
    }
}
