package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AlarmRingActivity

class SmartAlarmReceiver : BroadcastReceiver() {
    companion object {
        const val EXTRA_ID = "alarm_id"
        const val EXTRA_LABEL = "alarm_label"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        context.startActivity(
            Intent(context, AlarmRingActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(EXTRA_ID, intent?.getStringExtra(EXTRA_ID))
                .putExtra(EXTRA_LABEL, intent?.getStringExtra(EXTRA_LABEL) ?: "Alarm")
        )
    }
}
