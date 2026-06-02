package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.overlay

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.MainActivity
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.R

/**
 * The post-call card. A single floating window drawn over whatever is on screen
 * when a call ends (normally the dialer), using SYSTEM_ALERT_WINDOW — the same
 * mechanism a dedicated after-call app uses. No second Flutter engine: the card
 * is plain Android views, so it is cheap and instant.
 *
 * Dismissal is deliberately easy and covers every way out:
 *  - the card's own close button,
 *  - a tap anywhere outside the card (the dimmed scrim),
 *  - the Back button/gesture (the window is focusable, so it receives the key),
 *  - Home / Recents / any "close system dialogs" event,
 *  - and a safety auto-dismiss timer.
 *
 * Actions the card can do natively (calendar) run from here; app-specific actions
 * (the private vault, quick note) launch [MainActivity] with an `after_call_action`
 * extra that the Dart side routes. Holding SYSTEM_ALERT_WINDOW also exempts us
 * from background-activity-start limits, so those launches work from the overlay.
 */
object AfterCallOverlay {

    private const val AUTO_DISMISS_MS = 12_000L
    const val EXTRA_ACTION = "after_call_action"
    const val ACTION_VAULT = "vault"
    const val ACTION_NOTE = "note"

    private val main = Handler(Looper.getMainLooper())
    private var view: View? = null
    // The exact WindowManager the card was added through. removeView must be
    // called on the same instance, or it throws and the card is orphaned.
    private var windowManager: WindowManager? = null
    private var appContextRef: Context? = null
    // Fires when Home/Recents is pressed (system broadcast) so we can dismiss.
    private var homeWatcher: BroadcastReceiver? = null
    private val autoDismiss = Runnable { dismiss() }

    fun show(context: Context) {
        val appContext = context.applicationContext
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !Settings.canDrawOverlays(appContext)
        ) {
            // Permission revoked since the feature was enabled — silently skip.
            return
        }
        main.post { present(appContext) }
    }

    fun dismiss() {
        main.post { removeCard() }
    }

    /** Tear down the current card. Must run on the main thread. */
    private fun removeCard() {
        main.removeCallbacks(autoDismiss)
        unregisterHomeWatcher()
        val v = view ?: return
        try {
            windowManager?.removeView(v)
        } catch (_: IllegalArgumentException) {
            // Already detached.
        }
        view = null
        windowManager = null
    }

    private fun present(appContext: Context) {
        // Replace any card still on screen from a previous call. present() already
        // runs on the main thread, so remove synchronously — posting it would race
        // the addView below and could tear down the card we're about to show.
        removeCard()
        appContextRef = appContext

        val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        // Full-screen, focusable, modal: focusable so it receives the Back key,
        // full-screen+modal so a tap outside the card lands on the scrim. No
        // FLAG_NOT_FOCUSABLE / FLAG_NOT_TOUCH_MODAL here — that was what made the
        // old card impossible to dismiss. FLAG_DIM_BEHIND dims the app underneath.
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_DIM_BEHIND,
            android.graphics.PixelFormat.TRANSLUCENT,
        ).apply {
            dimAmount = 0.45f
            gravity = Gravity.TOP
        }

        val root = buildRoot(appContext)
        try {
            wm.addView(root, params)
            view = root
            windowManager = wm
            registerHomeWatcher(appContext)
            main.removeCallbacks(autoDismiss)
            main.postDelayed(autoDismiss, AUTO_DISMISS_MS)
        } catch (_: Exception) {
            view = null
            windowManager = null
        }
    }

    // --- dismissal plumbing ---------------------------------------------------

    /** Root that catches the Back key so the overlay can close on Back. */
    private class OverlayRoot(
        context: Context,
        private val onBack: () -> Unit,
    ) : FrameLayout(context) {
        override fun dispatchKeyEvent(event: KeyEvent): Boolean {
            if (event.keyCode == KeyEvent.KEYCODE_BACK &&
                event.action == KeyEvent.ACTION_UP
            ) {
                onBack()
                return true
            }
            return super.dispatchKeyEvent(event)
        }
    }

    private fun registerHomeWatcher(appContext: Context) {
        if (homeWatcher != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_CLOSE_SYSTEM_DIALOGS) dismiss()
            }
        }
        val filter = IntentFilter(Intent.ACTION_CLOSE_SYSTEM_DIALOGS)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                appContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                appContext.registerReceiver(receiver, filter)
            }
            homeWatcher = receiver
        } catch (_: Exception) {
        }
    }

    private fun unregisterHomeWatcher() {
        val receiver = homeWatcher ?: return
        try {
            appContextRef?.unregisterReceiver(receiver)
        } catch (_: Exception) {
        }
        homeWatcher = null
    }

    // --- view construction ----------------------------------------------------

    private fun buildRoot(ctx: Context): View {
        val root = OverlayRoot(ctx) { dismiss() }.apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            isClickable = true
            // Tap on the dimmed area (anywhere off the card) closes the overlay.
            setOnClickListener { dismiss() }
        }

        val cardParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
        ).apply {
            gravity = Gravity.TOP
            val side = dp(ctx, 12f)
            setMargins(side, statusBarHeight(ctx) + dp(ctx, 8f), side, side)
        }
        root.addView(buildCard(ctx), cardParams)
        return root
    }

    private fun buildCard(ctx: Context): View {
        val pad = dp(ctx, 18f)
        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad, pad, pad)
            background = GradientDrawable().apply {
                cornerRadius = dp(ctx, 22f).toFloat()
                setColor(Color.parseColor("#1C1C1E"))
            }
            // Swallow taps so they don't fall through to the scrim and dismiss.
            isClickable = true
        }

        val header = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        header.addView(
            TextView(ctx).apply {
                text = "Call ended"
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            },
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
        )
        header.addView(closeButton(ctx))
        card.addView(header)

        card.addView(
            TextView(ctx).apply {
                text = "Quick actions"
                setTextColor(Color.parseColor("#8E8E93"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setPadding(0, dp(ctx, 4f), 0, dp(ctx, 16f))
            },
        )

        val row = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
        row.addView(actionItem(ctx, R.drawable.ic_after_call_alarm, "Alarm", "#F5A623") {
            launchFeature(ctx, "features.ClockActivity")
            dismiss()
        })
        row.addView(actionItem(ctx, R.drawable.ic_after_call_calendar, "Calendar", "#3B82F6") {
            openCalendar(ctx)
            dismiss()
        })
        row.addView(actionItem(ctx, R.drawable.ic_after_call_vault, "Vault", "#14B8A6") {
            launchApp(ctx, ACTION_VAULT)
            dismiss()
        })
        row.addView(actionItem(ctx, R.drawable.ic_after_call_note, "Note", "#8B5CF6") {
            launchApp(ctx, ACTION_NOTE)
            dismiss()
        })
        card.addView(row)

        return card
    }

    private fun closeButton(ctx: Context): View {
        val size = dp(ctx, 36f)
        return ImageView(ctx).apply {
            setImageResource(R.drawable.ic_after_call_close)
            scaleType = ImageView.ScaleType.FIT_CENTER
            setPadding(dp(ctx, 9f), dp(ctx, 9f), dp(ctx, 9f), dp(ctx, 9f))
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#2A2A2D"))
            }
            layoutParams = LinearLayout.LayoutParams(size, size)
            isClickable = true
            contentDescription = "Close"
            setOnClickListener { dismiss() }
        }
    }

    private fun actionItem(
        ctx: Context,
        iconRes: Int,
        label: String,
        circleColor: String,
        onTap: () -> Unit,
    ): View {
        val circleSize = dp(ctx, 52f)
        val circle = ImageView(ctx).apply {
            setImageResource(iconRes)
            scaleType = ImageView.ScaleType.FIT_CENTER
            setPadding(dp(ctx, 8f), dp(ctx, 8f), dp(ctx, 8f), dp(ctx, 8f))
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor(circleColor))
            }
        }
        val caption = TextView(ctx).apply {
            text = label
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setPadding(0, dp(ctx, 6f), 0, 0)
        }
        return LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            isClickable = true
            setOnClickListener { onTap() }
            addView(circle, LinearLayout.LayoutParams(circleSize, circleSize))
            addView(caption)
            layoutParams = LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f,
            )
        }
    }

    // --- actions --------------------------------------------------------------

    private fun openCalendar(ctx: Context) {
        try {
            val intent = Intent(Intent.ACTION_INSERT)
                .setData(CalendarContract.Events.CONTENT_URI)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(intent)
        } catch (_: Exception) {
        }
    }

    private fun launchApp(ctx: Context, action: String) {
        try {
            val intent = Intent(ctx, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(EXTRA_ACTION, action)
            ctx.startActivity(intent)
        } catch (_: Exception) {
        }
    }

    private fun launchFeature(ctx: Context, alias: String) {
        try {
            val intent = Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .setClassName(ctx.packageName, "${ctx.packageName}.$alias")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(intent)
        } catch (_: Exception) {
        }
    }

    // --- helpers --------------------------------------------------------------

    private fun statusBarHeight(ctx: Context): Int {
        val id = ctx.resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) ctx.resources.getDimensionPixelSize(id) else dp(ctx, 24f)
    }

    private fun dp(ctx: Context, value: Float): Int =
        (value * ctx.resources.displayMetrics.density).toInt()
}
