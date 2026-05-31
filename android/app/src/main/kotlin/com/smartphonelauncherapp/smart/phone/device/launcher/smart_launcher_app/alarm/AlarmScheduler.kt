package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.MainActivity
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.receivers.SmartAlarmReceiver
import java.util.Calendar

/**
 * Schedules / cancels launcher-owned alarms with [AlarmManager.setAlarmClock]
 * (Doze-exempt, shows the system status-bar alarm icon) and recomputes repeat
 * occurrences. The next-occurrence math mirrors `ClockService.nextTrigger` on
 * the Dart side so both agree on timing.
 */
object AlarmScheduler {
    const val SNOOZE_SUFFIX = "#snooze"

    fun schedule(context: Context, spec: AlarmSpec): Boolean {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return false
        val broadcast = PendingIntent.getBroadcast(
            context,
            requestCode(spec.id),
            Intent(context, SmartAlarmReceiver::class.java)
                .putExtra(SmartAlarmReceiver.EXTRA_ID, spec.id),
            piFlags(),
        )
        // Tapping the upcoming-alarm chip opens the launcher.
        val showIntent = PendingIntent.getActivity(
            context,
            requestCode(spec.id) + 1,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            piFlags(),
        )
        return try {
            am.setAlarmClock(AlarmManager.AlarmClockInfo(spec.triggerAtMillis, showIntent), broadcast)
            AlarmStore.put(context, spec)
            true
        } catch (e: SecurityException) {
            false
        }
    }

    fun cancel(context: Context, id: String) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        val pi = PendingIntent.getBroadcast(
            context,
            requestCode(id),
            Intent(context, SmartAlarmReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or immutableFlag(),
        )
        if (pi != null) am?.cancel(pi)
        AlarmStore.remove(context, id)
    }

    /** Re-arms every stored alarm after a reboot / app update. */
    fun rescheduleAll(context: Context) {
        val now = System.currentTimeMillis()
        for (spec in AlarmStore.all(context)) {
            if (spec.id.endsWith(SNOOZE_SUFFIX)) {
                // Snoozes are transient; drop any that lapsed while powered off.
                if (spec.triggerAtMillis <= now) AlarmStore.remove(context, spec.id)
                else schedule(context, spec)
                continue
            }
            if (spec.isRepeating) {
                schedule(context, spec.copy(triggerAtMillis = nextTriggerFor(spec, now)))
            } else if (spec.triggerAtMillis > now) {
                schedule(context, spec)
            } else {
                // One-shot already in the past: it never fired (powered off), so
                // surface it as fired/missed and stop tracking it.
                if (spec.kind == "alarm") AlarmStore.markFired(context, spec.id)
                AlarmStore.remove(context, spec.id)
            }
        }
    }

    /** Next fire time for [spec] at/after [fromMillis] (repeat-aware). */
    fun nextTriggerFor(spec: AlarmSpec, fromMillis: Long): Long {
        if (spec.repeatDays.isEmpty()) {
            val c = baseCalendar(fromMillis, spec)
            if (c.timeInMillis <= fromMillis) c.add(Calendar.DAY_OF_YEAR, 1)
            return c.timeInMillis
        }
        for (add in 0..7) {
            val c = baseCalendar(fromMillis, spec).apply { add(Calendar.DAY_OF_YEAR, add) }
            // Re-apply h:m after the day shift.
            c.set(Calendar.HOUR_OF_DAY, spec.hour)
            c.set(Calendar.MINUTE, spec.minute)
            c.set(Calendar.SECOND, 0)
            c.set(Calendar.MILLISECOND, 0)
            val iso = toIsoWeekday(c.get(Calendar.DAY_OF_WEEK))
            if (spec.repeatDays.contains(iso) && c.timeInMillis > fromMillis) return c.timeInMillis
        }
        return fromMillis + 24L * 60 * 60 * 1000
    }

    fun requestCode(id: String): Int = id.hashCode()

    private fun baseCalendar(fromMillis: Long, spec: AlarmSpec): Calendar =
        Calendar.getInstance().apply {
            timeInMillis = fromMillis
            set(Calendar.HOUR_OF_DAY, spec.hour)
            set(Calendar.MINUTE, spec.minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

    private fun toIsoWeekday(calendarDay: Int): Int = when (calendarDay) {
        Calendar.MONDAY -> 1
        Calendar.TUESDAY -> 2
        Calendar.WEDNESDAY -> 3
        Calendar.THURSDAY -> 4
        Calendar.FRIDAY -> 5
        Calendar.SATURDAY -> 6
        Calendar.SUNDAY -> 7
        else -> 1
    }

    private fun immutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

    private fun piFlags(): Int = PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
}
