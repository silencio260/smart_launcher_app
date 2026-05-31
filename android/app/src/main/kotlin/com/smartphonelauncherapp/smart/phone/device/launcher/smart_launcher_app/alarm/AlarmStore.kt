package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.alarm

import android.content.Context
import org.json.JSONObject

/**
 * Durable native mirror of every scheduled alarm/timer, as JSON in
 * SharedPreferences. This is what [AlarmScheduler.rescheduleAll] reads after a
 * reboot and what the ring service falls back to. Dart owns the user-facing
 * model in Hive; this store exists purely so the OS-level schedule survives
 * without the Flutter engine.
 */
object AlarmStore {
    private const val PREFS = "smart_alarm_specs"
    private const val KEY_FIRED = "__fired_oneshot_ids"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun put(context: Context, spec: AlarmSpec) {
        prefs(context).edit().putString(spec.id, spec.toJson().toString()).apply()
    }

    fun get(context: Context, id: String): AlarmSpec? {
        val raw = prefs(context).getString(id, null) ?: return null
        return try {
            AlarmSpec.fromJson(JSONObject(raw))
        } catch (e: Exception) {
            null
        }
    }

    fun remove(context: Context, id: String) {
        prefs(context).edit().remove(id).apply()
    }

    fun all(context: Context): List<AlarmSpec> {
        val out = mutableListOf<AlarmSpec>()
        for ((key, value) in prefs(context).all) {
            if (key == KEY_FIRED) continue
            (value as? String)?.let {
                try {
                    out.add(AlarmSpec.fromJson(JSONObject(it)))
                } catch (_: Exception) {
                }
            }
        }
        return out
    }

    /** Records that a one-shot alarm has fired so Dart can disable it on next open. */
    fun markFired(context: Context, id: String) {
        val current = prefs(context).getStringSet(KEY_FIRED, emptySet()) ?: emptySet()
        val updated = current.toMutableSet().apply { add(id) }
        prefs(context).edit().putStringSet(KEY_FIRED, updated).apply()
    }

    /** Returns and clears the set of fired one-shot alarm ids. */
    fun consumeFired(context: Context): List<String> {
        val current = prefs(context).getStringSet(KEY_FIRED, emptySet()) ?: emptySet()
        val list = current.toList()
        prefs(context).edit().remove(KEY_FIRED).apply()
        return list
    }
}
