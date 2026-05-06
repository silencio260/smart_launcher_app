package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.provider.CalendarContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class CalendarChannel(private val activity: Activity) {

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.genrevibes.smartlauncher/calendar")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNextEvent" -> {
                        try {
                            result.success(getNextEvent())
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }
                    "getEventsToday" -> {
                        try {
                            result.success(getEventsToday())
                        } catch (e: Exception) {
                            result.success(emptyList<Map<String, Any?>>())
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getNextEvent(): Map<String, Any?>? {
        val now = System.currentTimeMillis()
        val end = now + 24 * 60 * 60 * 1000L // next 24h
        val cursor = activity.contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            arrayOf(
                CalendarContract.Events.TITLE,
                CalendarContract.Events.DTSTART,
                CalendarContract.Events.DTEND,
                CalendarContract.Events.EVENT_LOCATION,
            ),
            "${CalendarContract.Events.DTSTART} >= ? AND ${CalendarContract.Events.DTSTART} <= ?",
            arrayOf(now.toString(), end.toString()),
            CalendarContract.Events.DTSTART + " ASC LIMIT 1"
        ) ?: return null

        return cursor.use {
            if (!it.moveToFirst()) return null
            mapOf(
                "title" to it.getString(0),
                "dtStart" to it.getLong(1),
                "dtEnd" to it.getLong(2),
                "location" to it.getString(3),
            )
        }
    }

    private fun getEventsToday(): List<Map<String, Any?>> {
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0); cal.set(Calendar.SECOND, 0)
        val startOfDay = cal.timeInMillis
        cal.set(Calendar.HOUR_OF_DAY, 23); cal.set(Calendar.MINUTE, 59); cal.set(Calendar.SECOND, 59)
        val endOfDay = cal.timeInMillis

        val cursor = activity.contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            arrayOf(
                CalendarContract.Events.TITLE,
                CalendarContract.Events.DTSTART,
                CalendarContract.Events.DTEND,
            ),
            "${CalendarContract.Events.DTSTART} >= ? AND ${CalendarContract.Events.DTSTART} <= ?",
            arrayOf(startOfDay.toString(), endOfDay.toString()),
            CalendarContract.Events.DTSTART + " ASC"
        ) ?: return emptyList()

        val results = mutableListOf<Map<String, Any?>>()
        cursor.use {
            while (it.moveToNext()) {
                results.add(mapOf(
                    "title" to it.getString(0),
                    "dtStart" to it.getLong(1),
                    "dtEnd" to it.getLong(2),
                ))
            }
        }
        return results
    }
}
