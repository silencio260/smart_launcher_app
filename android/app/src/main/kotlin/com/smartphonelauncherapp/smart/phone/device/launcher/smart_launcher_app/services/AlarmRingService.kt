package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.alarm.AlarmNotifications
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.alarm.AlarmScheduler
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.alarm.AlarmSpec
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.alarm.AlarmStore
import org.json.JSONObject

/**
 * Foreground service that owns the ringing experience: looping alarm-stream
 * playback (custom / system / default tone), vibration, a wake lock, optional
 * gradual volume, and an auto-silence timeout. Snooze/Dismiss are delivered as
 * service actions (from the activity buttons or the notification actions).
 *
 * Living in a service rather than the activity means the alarm keeps ringing
 * even if the full-screen activity is destroyed.
 */
class AlarmRingService : Service() {
    companion object {
        const val ACTION_START = "com.genrevibes.smartlauncher.alarm.START"
        const val ACTION_SNOOZE = "com.genrevibes.smartlauncher.alarm.SNOOZE"
        const val ACTION_DISMISS = "com.genrevibes.smartlauncher.alarm.DISMISS"

        /** Broadcast the ring activity listens for so it can close itself. */
        const val ACTION_RING_FINISHED = "com.genrevibes.smartlauncher.alarm.RING_FINISHED"

        const val EXTRA_ID = "alarm_id"
        const val EXTRA_SPEC = "alarm_spec"

        private const val WAKE_TAG = "smartlauncher:alarm_ring"
        private const val RAMP_STEP_MS = 3000L
    }

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private var autoSilence: Runnable? = null
    private var volumeRamp: Runnable? = null
    private var rampVolume = 0.1f
    private var currentSpec: AlarmSpec? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SNOOZE -> {
                val spec = loadSpec(intent)
                if (spec != null) snooze(spec) else finishRing()
            }
            ACTION_DISMISS -> dismiss(loadSpec(intent))
            else -> {
                val spec = loadSpec(intent)
                if (spec == null) {
                    stopSelf()
                } else {
                    startRinging(spec)
                }
            }
        }
        return START_STICKY
    }

    private fun loadSpec(intent: Intent?): AlarmSpec? {
        intent?.getStringExtra(EXTRA_SPEC)?.let { json ->
            try {
                return AlarmSpec.fromJson(JSONObject(json))
            } catch (_: Exception) {
            }
        }
        val id = intent?.getStringExtra(EXTRA_ID)
        if (id != null) {
            AlarmStore.get(this, id)?.let { return it }
        }
        return currentSpec
    }

    private fun startRinging(spec: AlarmSpec) {
        currentSpec = spec
        val notification = AlarmNotifications.buildRingNotification(this, spec)
        startForegroundCompat(notification)
        acquireWakeLock(spec)
        playSound(spec)
        if (spec.vibrate) startVibration()
        scheduleAutoSilence(spec)
    }

    private fun startForegroundCompat(notification: Notification) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    AlarmNotifications.RING_NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                startForeground(AlarmNotifications.RING_NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            try {
                startForeground(AlarmNotifications.RING_NOTIFICATION_ID, notification)
            } catch (_: Exception) {
            }
        }
    }

    private fun acquireWakeLock(spec: AlarmSpec) {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val timeout = (spec.autoSilenceMinutes.coerceIn(1, 30)) * 60_000L + 60_000L
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_TAG).apply {
                setReferenceCounted(false)
                acquire(timeout)
            }
        } catch (_: Exception) {
        }
    }

    private fun playSound(spec: AlarmSpec) {
        rampVolume = if (spec.graduallyIncreaseVolume) 0.1f else 1f
        val primary = spec.ringtoneUri?.let { runCatching { Uri.parse(it) }.getOrNull() }
        if (!tryPlay(primary)) {
            val fallback = RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            tryPlay(fallback)
        }
        if (spec.graduallyIncreaseVolume) startVolumeRamp()
    }

    private fun tryPlay(uri: Uri?): Boolean {
        if (uri == null) return false
        return try {
            mediaPlayer?.release()
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                isLooping = true
                setDataSource(this@AlarmRingService, uri)
                setVolume(rampVolume, rampVolume)
                prepare()
                start()
            }
            true
        } catch (e: Exception) {
            mediaPlayer?.release()
            mediaPlayer = null
            false
        }
    }

    private fun startVolumeRamp() {
        volumeRamp = object : Runnable {
            override fun run() {
                rampVolume = (rampVolume + 0.12f).coerceAtMost(1f)
                try {
                    mediaPlayer?.setVolume(rampVolume, rampVolume)
                } catch (_: Exception) {
                }
                if (rampVolume < 1f) handler.postDelayed(this, RAMP_STEP_MS)
            }
        }.also { handler.postDelayed(it, RAMP_STEP_MS) }
    }

    private fun startVibration() {
        try {
            vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            val pattern = longArrayOf(0, 600, 500, 600, 800)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        } catch (_: Exception) {
        }
    }

    private fun scheduleAutoSilence(spec: AlarmSpec) {
        if (spec.autoSilenceMinutes <= 0) return
        autoSilence = Runnable { dismiss(currentSpec) }
            .also { handler.postDelayed(it, spec.autoSilenceMinutes * 60_000L) }
    }

    private fun snooze(spec: AlarmSpec) {
        val base = baseId(spec.id)
        val snoozeSpec = spec.copy(
            id = base + AlarmScheduler.SNOOZE_SUFFIX,
            triggerAtMillis = System.currentTimeMillis() + spec.snoozeMinutes.coerceAtLeast(1) * 60_000L,
            repeatDays = emptyList(),
            kind = "alarm",
        )
        AlarmScheduler.schedule(this, snoozeSpec)
        finishRing()
    }

    private fun dismiss(spec: AlarmSpec?) {
        if (spec != null) {
            val base = baseId(spec.id)
            // Cancel any pending snooze for this alarm.
            AlarmScheduler.cancel(this, base + AlarmScheduler.SNOOZE_SUFFIX)
            if (spec.id.endsWith(AlarmScheduler.SNOOZE_SUFFIX)) {
                AlarmStore.remove(this, spec.id)
            }
        }
        finishRing()
    }

    private fun baseId(id: String): String =
        if (id.endsWith(AlarmScheduler.SNOOZE_SUFFIX)) {
            id.substring(0, id.length - AlarmScheduler.SNOOZE_SUFFIX.length)
        } else {
            id
        }

    private fun finishRing() {
        stopPlayback()
        AlarmNotifications.cancel(this)
        sendBroadcast(Intent(ACTION_RING_FINISHED).setPackage(packageName))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun stopPlayback() {
        autoSilence?.let { handler.removeCallbacks(it) }
        volumeRamp?.let { handler.removeCallbacks(it) }
        autoSilence = null
        volumeRamp = null
        try {
            mediaPlayer?.stop()
        } catch (_: Exception) {
        }
        mediaPlayer?.release()
        mediaPlayer = null
        try {
            vibrator?.cancel()
        } catch (_: Exception) {
        }
        if (wakeLock?.isHeld == true) {
            try {
                wakeLock?.release()
            } catch (_: Exception) {
            }
        }
        wakeLock = null
    }

    override fun onDestroy() {
        stopPlayback()
        super.onDestroy()
    }
}
