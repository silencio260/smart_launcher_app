package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.alarm

import org.json.JSONArray
import org.json.JSONObject

/**
 * Full description of a scheduled alarm or timer. Persisted natively (as JSON
 * in [AlarmStore]) so the broadcast receiver, ring service, repeat logic and
 * boot-time recovery all work without the Flutter engine running.
 *
 * [repeatDays] uses Dart's `DateTime.weekday` convention: 1 = Mon … 7 = Sun.
 * [kind] is "alarm" or "timer".
 */
data class AlarmSpec(
    val id: String,
    val triggerAtMillis: Long,
    val label: String,
    val hour: Int,
    val minute: Int,
    val repeatDays: List<Int>,
    val ringtoneUri: String?,
    val ringtoneTitle: String,
    val vibrate: Boolean,
    val graduallyIncreaseVolume: Boolean,
    val autoSilenceMinutes: Int,
    val snoozeMinutes: Int,
    val kind: String,
) {
    val isRepeating: Boolean get() = kind == "alarm" && repeatDays.isNotEmpty()

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("triggerAtMillis", triggerAtMillis)
        put("label", label)
        put("hour", hour)
        put("minute", minute)
        put("repeatDays", JSONArray(repeatDays))
        put("ringtoneUri", ringtoneUri ?: JSONObject.NULL)
        put("ringtoneTitle", ringtoneTitle)
        put("vibrate", vibrate)
        put("graduallyIncreaseVolume", graduallyIncreaseVolume)
        put("autoSilenceMinutes", autoSilenceMinutes)
        put("snoozeMinutes", snoozeMinutes)
        put("kind", kind)
    }

    companion object {
        fun fromJson(o: JSONObject): AlarmSpec {
            val days = mutableListOf<Int>()
            o.optJSONArray("repeatDays")?.let { arr ->
                for (i in 0 until arr.length()) days.add(arr.getInt(i))
            }
            val uri = if (o.isNull("ringtoneUri")) null
            else o.optString("ringtoneUri", "").ifEmpty { null }
            return AlarmSpec(
                id = o.optString("id"),
                triggerAtMillis = o.optLong("triggerAtMillis"),
                label = o.optString("label", "Alarm"),
                hour = o.optInt("hour", 7),
                minute = o.optInt("minute", 0),
                repeatDays = days,
                ringtoneUri = uri,
                ringtoneTitle = o.optString("ringtoneTitle", "Default"),
                vibrate = o.optBoolean("vibrate", true),
                graduallyIncreaseVolume = o.optBoolean("graduallyIncreaseVolume", false),
                autoSilenceMinutes = o.optInt("autoSilenceMinutes", 10),
                snoozeMinutes = o.optInt("snoozeMinutes", 5),
                kind = o.optString("kind", "alarm"),
            )
        }

        /** Builds a spec from a MethodChannel argument map; null if no id. */
        fun fromArguments(args: Map<String, Any?>): AlarmSpec? {
            val id = args["id"] as? String ?: return null
            val daysRaw = args["repeatDays"] as? List<*> ?: emptyList<Any?>()
            val days = daysRaw.mapNotNull { (it as? Number)?.toInt() }
            val uri = (args["ringtoneUri"] as? String)?.ifEmpty { null }
            return AlarmSpec(
                id = id,
                triggerAtMillis = (args["triggerAtMillis"] as? Number)?.toLong() ?: 0L,
                label = args["label"] as? String ?: "Alarm",
                hour = (args["hour"] as? Number)?.toInt() ?: 7,
                minute = (args["minute"] as? Number)?.toInt() ?: 0,
                repeatDays = days,
                ringtoneUri = uri,
                ringtoneTitle = args["ringtoneTitle"] as? String ?: "Default",
                vibrate = args["vibrate"] as? Boolean ?: true,
                graduallyIncreaseVolume = args["graduallyIncreaseVolume"] as? Boolean ?: false,
                autoSilenceMinutes = (args["autoSilenceMinutes"] as? Number)?.toInt() ?: 10,
                snoozeMinutes = (args["snoozeMinutes"] as? Number)?.toInt() ?: 5,
                kind = args["kind"] as? String ?: "alarm",
            )
        }
    }
}
