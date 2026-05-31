package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features

import android.app.Activity
import android.graphics.Color
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.receivers.SmartAlarmReceiver

class AlarmRingActivity : Activity() {
    private var ringtone: Ringtone? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val label = intent.getStringExtra(SmartAlarmReceiver.EXTRA_LABEL) ?: "Alarm"
        buildUi(label)
        ring()
    }

    override fun onDestroy() {
        ringtone?.stop()
        super.onDestroy()
    }

    private fun buildUi(label: String) {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
            setBackgroundColor(Color.BLACK)
        }
        root.addView(
            TextView(this).apply {
                text = label
                setTextColor(Color.WHITE)
                textSize = 36f
                gravity = Gravity.CENTER
            },
        )
        root.addView(
            TextView(this).apply {
                text = "Time to wake up"
                setTextColor(Color.rgb(245, 166, 35))
                textSize = 18f
                gravity = Gravity.CENTER
                setPadding(0, 12, 0, 42)
            },
        )
        root.addView(
            Button(this).apply {
                text = "Dismiss"
                setOnClickListener { finish() }
            },
        )
        setContentView(root)
    }

    private fun ring() {
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ringtone = RingtoneManager.getRingtone(this, uri).also { it.play() }
        } catch (_: Exception) {
        }
        try {
            val vibrator = getSystemService(Vibrator::class.java)
            vibrator?.vibrate(
                VibrationEffect.createWaveform(longArrayOf(0, 600, 500, 600), 0),
            )
        } catch (_: Exception) {
        }
    }
}
