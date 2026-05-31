package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.alarm.AlarmScheduler
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.alarm.AlarmStore
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services.AlarmRingService

/**
 * Fired by AlarmManager when an alarm/timer is due. Arranges the next repeat
 * occurrence (or marks a one-shot as fired) BEFORE handing off to the
 * foreground ring service, so follow-up scheduling survives even if the ring
 * service is killed. Everything here runs without the Flutter engine.
 */
class SmartAlarmReceiver : BroadcastReceiver() {
    companion object {
        const val EXTRA_ID = "alarm_id"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val id = intent?.getStringExtra(EXTRA_ID) ?: return
        val spec = AlarmStore.get(context, id) ?: return
        val now = System.currentTimeMillis()

        if (spec.isRepeating) {
            // Re-arm for the next selected weekday (skip the current minute).
            val next = AlarmScheduler.nextTriggerFor(spec, now + 60_000L)
            AlarmScheduler.schedule(context, spec.copy(triggerAtMillis = next))
        } else {
            if (spec.kind == "alarm" && !spec.id.endsWith(AlarmScheduler.SNOOZE_SUFFIX)) {
                AlarmStore.markFired(context, spec.id)
            }
            AlarmStore.remove(context, spec.id)
        }

        val service = Intent(context, AlarmRingService::class.java)
            .setAction(AlarmRingService.ACTION_START)
            .putExtra(AlarmRingService.EXTRA_ID, spec.id)
            .putExtra(AlarmRingService.EXTRA_SPEC, spec.toJson().toString())
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(service)
            } else {
                context.startService(service)
            }
        } catch (_: Exception) {
            // If the foreground-service start is somehow disallowed, the
            // setAlarmClock show-intent and any posted notification remain the
            // user's path back in.
        }
    }
}
