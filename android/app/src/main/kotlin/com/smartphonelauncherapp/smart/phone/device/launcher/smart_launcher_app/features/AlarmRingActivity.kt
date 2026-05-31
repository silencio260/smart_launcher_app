package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features

import android.app.Activity
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services.AlarmRingService
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Full-screen ringing UI shown over the lockscreen via the alarm's full-screen
 * intent. The sound/vibration/wake-lock all live in [AlarmRingService]; this
 * activity is purely the UI + Snooze/Dismiss controls and a live clock. It
 * closes itself when the service broadcasts that the ring finished (e.g.
 * auto-silence, or a dismiss from the notification).
 */
class AlarmRingActivity : Activity() {
    companion object {
        const val EXTRA_ID = "alarm_id"
        const val EXTRA_LABEL = "alarm_label"
        const val EXTRA_KIND = "alarm_kind"

        private const val ACCENT = 0xFFF5A623.toInt()
        private const val SURFACE = 0xFF1C1C1E.toInt()

        fun ringIntent(context: Context, id: String, label: String, kind: String): Intent =
            Intent(context, AlarmRingActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(EXTRA_ID, id)
                .putExtra(EXTRA_LABEL, label)
                .putExtra(EXTRA_KIND, kind)
    }

    private val handler = Handler(Looper.getMainLooper())
    private var clockTick: Runnable? = null
    private var timeView: TextView? = null
    private var alarmId: String? = null

    private val finishReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            finish()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showWhenLockedAndTurnScreenOn()

        alarmId = intent.getStringExtra(EXTRA_ID)
        val label = intent.getStringExtra(EXTRA_LABEL) ?: "Alarm"
        val kind = intent.getStringExtra(EXTRA_KIND) ?: "alarm"
        setContentView(buildUi(label, kind))
        startClock()

        val filter = IntentFilter(AlarmRingService.ACTION_RING_FINISHED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(finishReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(finishReceiver, filter)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun showWhenLockedAndTurnScreenOn() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            (getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager)
                ?.requestDismissKeyguard(this, null)
        }
    }

    private fun buildUi(label: String, kind: String): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.BLACK)
            setPadding(dp(32), dp(48), dp(32), dp(48))
        }

        root.addView(
            TextView(this).apply {
                text = if (kind == "timer") "TIMER" else "ALARM"
                setTextColor(ACCENT)
                textSize = 16f
                letterSpacing = 0.3f
                gravity = Gravity.CENTER
                typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            },
        )

        timeView = TextView(this).apply {
            text = currentTime()
            setTextColor(Color.WHITE)
            textSize = 72f
            gravity = Gravity.CENTER
            typeface = Typeface.create("sans-serif-thin", Typeface.NORMAL)
            setPadding(0, dp(8), 0, dp(4))
        }
        root.addView(timeView)

        root.addView(
            TextView(this).apply {
                text = label
                setTextColor(Color.WHITE)
                textSize = 24f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, dp(56))
            },
        )

        val buttons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        if (kind != "timer") {
            buttons.addView(
                roundButton("Snooze", SURFACE, Color.WHITE) { send(AlarmRingService.ACTION_SNOOZE) },
            )
            buttons.addView(spacer())
        }
        buttons.addView(
            roundButton("Dismiss", ACCENT, Color.BLACK) { send(AlarmRingService.ACTION_DISMISS) },
        )
        root.addView(buttons)
        return root
    }

    private fun roundButton(text: String, bg: Int, fg: Int, onClick: () -> Unit): View =
        TextView(this).apply {
            this.text = text
            setTextColor(fg)
            textSize = 18f
            gravity = Gravity.CENTER
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            setPadding(dp(28), dp(18), dp(28), dp(18))
            background = GradientDrawable().apply {
                cornerRadius = dp(36).toFloat()
                setColor(bg)
            }
            isClickable = true
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(dp(150), ViewGroup.LayoutParams.WRAP_CONTENT)
        }

    private fun spacer(): View = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(dp(20), 1)
    }

    private fun send(action: String) {
        val svc = Intent(this, AlarmRingService::class.java)
            .setAction(action)
            .putExtra(AlarmRingService.EXTRA_ID, alarmId)
        try {
            startService(svc)
        } catch (_: Exception) {
        }
        finish()
    }

    private fun startClock() {
        clockTick = object : Runnable {
            override fun run() {
                timeView?.text = currentTime()
                handler.postDelayed(this, 1000)
            }
        }.also { handler.postDelayed(it, 1000) }
    }

    private fun currentTime(): String =
        SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        clockTick?.let { handler.removeCallbacks(it) }
        try {
            unregisterReceiver(finishReceiver)
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Ignore back so the alarm must be explicitly snoozed or dismissed.
    }
}
