package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.overlay

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.Drawable
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
import android.widget.ScrollView
import android.widget.TextView
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.MainActivity
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.R

/**
 * The post-call panel. A single native window drawn over whatever is on screen
 * when a call ends (normally the dialer), using SYSTEM_ALERT_WINDOW — the same
 * mechanism a dedicated after-call app uses. No second Flutter engine: the panel
 * is plain Android views, so it is cheap and instant.
 *
 * Dismissal is deliberately easy and covers every way out:
 *  - the panel's own close button,
 *  - the Back button/gesture (the window is focusable, so it receives the key),
 *  - Home / Recents / any "close system dialogs" event.
 *
 * Actions the panel can do natively (calendar) run from here; app-specific actions
 * (the private vault, quick note) launch [MainActivity] with an `after_call_action`
 * extra that the Dart side routes. Holding SYSTEM_ALERT_WINDOW also exempts us
 * from background-activity-start limits, so those launches work from the overlay.
 */
object AfterCallOverlay {

    const val EXTRA_ACTION = "after_call_action"
    const val ACTION_VAULT = "vault"
    const val ACTION_NOTE = "note"
    const val ACTION_SETTINGS = "settings"

    private val main = Handler(Looper.getMainLooper())
    private var view: View? = null
    // The exact WindowManager the card was added through. removeView must be
    // called on the same instance, or it throws and the card is orphaned.
    private var windowManager: WindowManager? = null
    private var appContextRef: Context? = null
    // Fires when Home/Recents is pressed (system broadcast) so we can dismiss.
    private var homeWatcher: BroadcastReceiver? = null

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
        // Full-screen and focusable so it receives Back. No caller identity or
        // call-log details are shown, keeping the feature as a privacy-light
        // post-call launcher action center.
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS,
            android.graphics.PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }

        val root = buildRoot(appContext)
        try {
            wm.addView(root, params)
            root.requestFocus()
            view = root
            windowManager = wm
            registerHomeWatcher(appContext)
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
            isFocusable = true
            isFocusableInTouchMode = true
            systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            setBackgroundColor(Color.BLACK)
        }

        val contentParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        ).apply {
            gravity = Gravity.TOP
        }
        root.addView(buildPanel(ctx), contentParams)

        val navHeight = navigationBarHeight(ctx)
        if (navHeight > 0) {
            root.addView(
                View(ctx).apply { setBackgroundColor(Color.BLACK) },
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    navHeight,
                ).apply { gravity = Gravity.BOTTOM },
            )
        }
        return root
    }

    private fun buildPanel(ctx: Context): View {
        val panel = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(
                dp(ctx, 16f),
                statusBarHeight(ctx) + dp(ctx, 8f),
                dp(ctx, 16f),
                navigationBarHeight(ctx) + dp(ctx, 24f),
            )
            isClickable = true
        }

        val header = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        header.addView(closeButton(ctx))
        header.addView(
            TextView(ctx).apply {
                text = "After Call"
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
                setTypeface(typeface, Typeface.BOLD)
            },
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
        )
        header.addView(settingsButton(ctx))
        panel.addView(header)

        panel.addView(
            TextView(ctx).apply {
                text = "Quick actions after your call"
                gravity = Gravity.CENTER
                setTextColor(Color.parseColor("#9A9A9A"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                setPadding(0, dp(ctx, 8f), 0, dp(ctx, 18f))
            },
        )

        val scroller = ScrollView(ctx).apply {
            isFillViewport = true
            overScrollMode = View.OVER_SCROLL_NEVER
        }
        val body = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
        }
        body.addView(summaryCard(ctx))

        val rowOne = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(ctx, 18f), 0, 0)
        }
        rowOne.addView(actionItem(ctx, featureIcon(ctx, "features.ClockActivity", R.drawable.ic_feature_clock_foreground), "Alarm") {
            launchFeature(ctx, "features.ClockActivity")
            dismiss()
        })
        rowOne.addView(actionItem(ctx, calendarIcon(ctx), "Calendar") {
            openCalendar(ctx)
            dismiss()
        })
        body.addView(rowOne)

        val rowTwo = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(ctx, 12f), 0, 0)
        }
        rowTwo.addView(actionItem(ctx, featureIcon(ctx, "features.FileLockerActivity", R.drawable.ic_feature_file_locker_foreground), "Vault") {
            launchApp(ctx, ACTION_VAULT)
            dismiss()
        })
        rowTwo.addView(actionItem(ctx, featureIcon(ctx, "features.NotesVaultActivity", R.drawable.ic_feature_notes_foreground), "Note") {
            launchApp(ctx, ACTION_NOTE)
            dismiss()
        })
        body.addView(rowTwo)

        scroller.addView(body)
        panel.addView(scroller, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            0,
            1f,
        ))

        return panel
    }

    private fun closeButton(ctx: Context): View {
        val size = dp(ctx, 36f)
        return ImageView(ctx).apply {
            setImageResource(R.drawable.ic_after_call_close)
            scaleType = ImageView.ScaleType.FIT_CENTER
            setPadding(dp(ctx, 7f), dp(ctx, 7f), dp(ctx, 7f), dp(ctx, 7f))
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.TRANSPARENT)
            }
            layoutParams = LinearLayout.LayoutParams(size, size)
            isClickable = true
            contentDescription = "Close"
            setOnClickListener { dismiss() }
        }
    }

    private fun settingsButton(ctx: Context): View {
        val size = dp(ctx, 36f)
        return ImageView(ctx).apply {
            setImageResource(R.drawable.ic_after_call_settings)
            setColorFilter(Color.WHITE)
            scaleType = ImageView.ScaleType.FIT_CENTER
            setPadding(dp(ctx, 7f), dp(ctx, 7f), dp(ctx, 7f), dp(ctx, 7f))
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.TRANSPARENT)
            }
            layoutParams = LinearLayout.LayoutParams(size, size)
            isClickable = true
            contentDescription = "After Call settings"
            setOnClickListener {
                launchApp(ctx, ACTION_SETTINGS)
                dismiss()
            }
        }
    }

    private fun summaryCard(ctx: Context): View {
        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(ctx, 20f), dp(ctx, 20f), dp(ctx, 20f), dp(ctx, 20f))
            background = roundedRect(ctx, "#111111", "#2A2A2A")
        }
        card.addView(
            TextView(ctx).apply {
                text = "Call ended"
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
                setTypeface(typeface, Typeface.BOLD)
            },
        )
        card.addView(
            TextView(ctx).apply {
                text = "Choose what you want to do next."
                setTextColor(Color.parseColor("#BDBDBD"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                setPadding(0, dp(ctx, 8f), 0, 0)
            },
        )
        return card
    }

    private fun actionItem(
        ctx: Context,
        icon: Drawable,
        label: String,
        onTap: () -> Unit,
    ): View {
        val circleSize = dp(ctx, 58f)
        val circle = ImageView(ctx).apply {
            setImageDrawable(icon)
            clearColorFilter()
            scaleType = ImageView.ScaleType.FIT_CENTER
            adjustViewBounds = true
            setPadding(0, 0, 0, 0)
            background = null
        }
        val caption = TextView(ctx).apply {
            text = label
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, dp(ctx, 6f), 0, 0)
        }
        return LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            isClickable = true
            setPadding(dp(ctx, 10f), dp(ctx, 18f), dp(ctx, 10f), dp(ctx, 18f))
            background = roundedRect(ctx, "#000000", "#FFFFFF")
            setOnClickListener { onTap() }
            addView(circle, LinearLayout.LayoutParams(circleSize, circleSize))
            addView(caption)
            layoutParams = LinearLayout.LayoutParams(
                0,
                dp(ctx, 144f),
                1f,
            ).apply { setMargins(dp(ctx, 4f), 0, dp(ctx, 4f), 0) }
        }
    }

    private fun roundedRect(
        ctx: Context,
        fill: String,
        stroke: String,
        radiusDp: Float = 18f,
    ): GradientDrawable =
        GradientDrawable().apply {
            cornerRadius = dp(ctx, radiusDp).toFloat()
            setColor(Color.parseColor(fill))
            setStroke(dp(ctx, 1f), Color.parseColor(stroke))
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

    private fun featureIcon(ctx: Context, alias: String, fallbackRes: Int): Drawable {
        val pm = ctx.packageManager
        return try {
            pm.getActivityIcon(ComponentName(ctx.packageName, "${ctx.packageName}.$alias"))
        } catch (_: Exception) {
            resourceIcon(ctx, fallbackRes)
        }
    }

    private fun calendarIcon(ctx: Context): Drawable {
        val pm = ctx.packageManager
        val intent = Intent(Intent.ACTION_INSERT).setData(CalendarContract.Events.CONTENT_URI)
        return try {
            intent.resolveActivity(pm)?.let { pm.getActivityIcon(it) }
                ?: resourceIcon(ctx, R.drawable.ic_after_call_calendar)
        } catch (_: Exception) {
            resourceIcon(ctx, R.drawable.ic_after_call_calendar)
        }
    }

    private fun resourceIcon(ctx: Context, resId: Int): Drawable =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            ctx.resources.getDrawable(resId, ctx.theme)
        } else {
            @Suppress("DEPRECATION")
            ctx.resources.getDrawable(resId)
        }

    private fun statusBarHeight(ctx: Context): Int {
        val id = ctx.resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) ctx.resources.getDimensionPixelSize(id) else dp(ctx, 24f)
    }

    private fun navigationBarHeight(ctx: Context): Int {
        val id = ctx.resources.getIdentifier("navigation_bar_height", "dimen", "android")
        return if (id > 0) ctx.resources.getDimensionPixelSize(id) else 0
    }

    private fun dp(ctx: Context, value: Float): Int =
        (value * ctx.resources.displayMetrics.density).toInt()
}
