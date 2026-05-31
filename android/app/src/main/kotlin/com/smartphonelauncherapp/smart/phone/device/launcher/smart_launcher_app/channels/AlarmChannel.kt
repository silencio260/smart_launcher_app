package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.AlarmClock
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.alarm.AlarmScheduler
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.alarm.AlarmSpec
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.alarm.AlarmStore
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services.AlarmRingService

class AlarmChannel(private val activity: Activity) {
    companion object {
        private const val REQUEST_RINGTONE = 8120
        private const val REQUEST_AUDIO = 8121
    }

    private var pendingRingtoneResult: MethodChannel.Result? = null
    private var pendingAudioResult: MethodChannel.Result? = null
    private var previewPlayer: MediaPlayer? = null

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
                    "openAlarmApp" -> result.success(launchAlarmIntent(AlarmClock.ACTION_SHOW_ALARMS))
                    "createAlarm" -> result.success(launchAlarmIntent(AlarmClock.ACTION_SET_ALARM))
                    "openTimer" -> result.success(launchAlarmIntent(AlarmClock.ACTION_SET_TIMER))
                    "openStopwatch" -> result.success(launchAlarmIntent(AlarmClock.ACTION_SHOW_TIMERS))
                    "canScheduleExactAlarms" -> result.success(canScheduleExactAlarms())
                    "requestExactAlarmAccess" -> {
                        requestExactAlarmAccess()
                        result.success(true)
                    }
                    "scheduleSmartAlarm" -> {
                        val args = call.arguments as? Map<String, Any?>
                        val spec = args?.let { AlarmSpec.fromArguments(it) }
                        result.success(
                            if (spec != null) AlarmScheduler.schedule(activity, spec) else false,
                        )
                    }
                    "cancelSmartAlarm" -> {
                        val id = call.argument<String>("id")
                        result.success(if (id != null) cancelSmartAlarm(id) else false)
                    }
                    "consumeFiredAlarms" -> result.success(AlarmStore.consumeFired(activity))
                    "pickSystemRingtone" ->
                        pickSystemRingtone(call.argument<String>("currentUri"), result)
                    "pickCustomAudio" -> pickCustomAudio(result)
                    "previewTone" -> {
                        previewTone(call.argument<String>("uri"))
                        result.success(null)
                    }
                    "stopPreview" -> {
                        stopPreview()
                        result.success(null)
                    }
                    "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                    "requestFullScreenIntentAccess" -> {
                        requestFullScreenIntentAccess()
                        result.success(true)
                    }
                    "isIgnoringBatteryOptimizations" ->
                        result.success(isIgnoringBatteryOptimizations())
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        when (requestCode) {
            REQUEST_RINGTONE -> {
                val result = pendingRingtoneResult ?: return true
                pendingRingtoneResult = null
                if (resultCode != Activity.RESULT_OK) {
                    result.success(null)
                    return true
                }
                val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
                }
                if (uri == null) {
                    result.success(null)
                    return true
                }
                val title = try {
                    RingtoneManager.getRingtone(activity, uri)?.getTitle(activity) ?: "Alarm sound"
                } catch (e: Exception) {
                    "Alarm sound"
                }
                result.success(mapOf("uri" to uri.toString(), "title" to title))
                return true
            }
            REQUEST_AUDIO -> {
                val result = pendingAudioResult ?: return true
                pendingAudioResult = null
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    result.success(null)
                    return true
                }
                try {
                    activity.contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                } catch (_: Exception) {
                }
                result.success(mapOf("uri" to uri.toString(), "title" to displayName(uri)))
                return true
            }
        }
        return false
    }

    private fun getNextAlarm(): Map<String, Any?>? {
        val am = activity.getSystemService(AlarmManager::class.java) ?: return null
        val clock = am.nextAlarmClock ?: return null
        return mapOf("triggerTime" to clock.triggerTime)
    }

    private fun launchAlarmIntent(action: String): Boolean {
        return try {
            val intent = Intent(action).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (action == AlarmClock.ACTION_SET_ALARM || action == AlarmClock.ACTION_SET_TIMER) {
                    putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                }
            }
            activity.startActivity(intent)
            true
        } catch (e: Exception) {
            try {
                val fallback = activity.packageManager.getLaunchIntentForPackage("com.google.android.deskclock")
                    ?: activity.packageManager.getLaunchIntentForPackage("com.android.deskclock")
                if (fallback != null) {
                    activity.startActivity(fallback)
                    true
                } else {
                    false
                }
            } catch (e2: Exception) {
                false
            }
        }
    }

    private fun canScheduleExactAlarms(): Boolean {
        val am = activity.getSystemService(AlarmManager::class.java) ?: return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
    }

    private fun requestExactAlarmAccess() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        try {
            activity.startActivity(
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                    .setData(Uri.parse("package:${activity.packageName}")),
            )
        } catch (_: Exception) {
            try {
                activity.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM))
            } catch (_: Exception) {
            }
        }
    }

    private fun cancelSmartAlarm(id: String): Boolean {
        AlarmScheduler.cancel(activity, id)
        AlarmScheduler.cancel(activity, id + AlarmScheduler.SNOOZE_SUFFIX)
        // If this alarm is ringing right now, stop it too.
        try {
            activity.startService(
                Intent(activity, AlarmRingService::class.java)
                    .setAction(AlarmRingService.ACTION_DISMISS)
                    .putExtra(AlarmRingService.EXTRA_ID, id),
            )
        } catch (_: Exception) {
        }
        return true
    }

    private fun pickSystemRingtone(currentUri: String?, result: MethodChannel.Result) {
        if (pendingRingtoneResult != null) {
            result.success(null)
            return
        }
        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
            putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Alarm sound")
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            putExtra(
                RingtoneManager.EXTRA_RINGTONE_DEFAULT_URI,
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
            )
            currentUri?.let {
                putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(it))
            }
        }
        pendingRingtoneResult = result
        try {
            activity.startActivityForResult(intent, REQUEST_RINGTONE)
        } catch (e: Exception) {
            pendingRingtoneResult = null
            result.success(null)
        }
    }

    private fun pickCustomAudio(result: MethodChannel.Result) {
        if (pendingAudioResult != null) {
            result.success(null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        pendingAudioResult = result
        try {
            activity.startActivityForResult(intent, REQUEST_AUDIO)
        } catch (e: Exception) {
            pendingAudioResult = null
            result.success(null)
        }
    }

    private fun previewTone(uriString: String?) {
        stopPreview()
        try {
            val uri = uriString?.let { Uri.parse(it) }
                ?: RingtoneManager.getActualDefaultRingtoneUri(activity, RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: return
            previewPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                isLooping = false
                setDataSource(activity, uri)
                setOnCompletionListener { stopPreview() }
                prepare()
                start()
            }
        } catch (e: Exception) {
            stopPreview()
        }
    }

    private fun stopPreview() {
        try {
            previewPlayer?.stop()
        } catch (_: Exception) {
        }
        previewPlayer?.release()
        previewPlayer = null
    }

    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        val nm = activity.getSystemService(NotificationManager::class.java) ?: return true
        return nm.canUseFullScreenIntent()
    }

    private fun requestFullScreenIntentAccess() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        try {
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                    .setData(Uri.parse("package:${activity.packageName}")),
            )
        } catch (_: Exception) {
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = activity.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return true
        return pm.isIgnoringBatteryOptimizations(activity.packageName)
    }

    private fun requestIgnoreBatteryOptimizations() {
        try {
            activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        } catch (_: Exception) {
        }
    }

    private fun displayName(uri: Uri): String {
        var name = "Custom sound"
        try {
            activity.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) name = cursor.getString(index) ?: name
                }
            }
        } catch (_: Exception) {
        }
        return name
    }
}
