package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.overlay

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
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
import android.widget.Toast
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.AppQueryHelper
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.SmartLauncherApplication
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.InstallAssistantChannel

/**
 * The Install/Uninstall Assistant card. Same SYSTEM_ALERT_WINDOW mechanism as the
 * after-call overlay, so it draws over whatever is on screen (e.g. the Play Store)
 * the instant the launcher process detects a package change — no Flutter UI needed.
 *
 * It's a polished dark bottom prompt: assistant header, large app icon + title,
 * two strong actions, and a "Don't show again" row that turns the feature off.
 *
 * Actions never bounce through an Activity. "Open" launches the app directly; the
 * launcher-state actions (add-to-home, hide, cleanup, disable) are stashed via
 * [InstallAssistantChannel.deliver] and applied by Dart on its next resume, with a
 * brief native toast for immediate feedback. Dismissal mirrors the after-call card:
 * ✕, a tap on the dimmed scrim, Back, Home/Recents, or an auto-dismiss timer.
 */
object InstallAssistantOverlay {

    private const val AUTO_DISMISS_MS = 12_000L

    // Palette matching the dark bottom prompt reference.
    private const val SHEET_BG = "#25262D"
    private const val TILE_BG = "#3A3E4D"
    private const val TEXT_PRIMARY = "#FFFFFF"
    private const val TEXT_SECONDARY = "#ADB2C1"
    private const val DISMISS_COLOR = "#53586A"
    private const val PRIMARY_START = "#0B6CFF"
    private const val PRIMARY_END = "#08A7FF"

    private val main = Handler(Looper.getMainLooper())
    private var view: View? = null
    private var windowManager: WindowManager? = null
    private var appContextRef: Context? = null
    private var homeWatcher: BroadcastReceiver? = null
    private val autoDismiss = Runnable { dismiss() }

    private data class CardAction(
        val label: String,
        val primary: Boolean,
        val onTap: () -> Unit,
    )

    // --- entry points ---------------------------------------------------------

    fun showInstalled(context: Context, pkg: String) {
        val appContext = context.applicationContext
        if (!canDraw(appContext)) return
        val pm = appContext.packageManager
        val label = try {
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
        } catch (_: Exception) {
            AppQueryHelper.lastKnownLabel(appContext, pkg) ?: pkg
        }
        val icon: Drawable? = try {
            pm.getApplicationIcon(pkg)
        } catch (_: Exception) {
            null
        }
        val actions = listOf(
            CardAction("Not now", false) {
                dismiss()
            },
            CardAction("Add", true) {
                InstallAssistantChannel.deliver("add_home:$pkg")
                toast(appContext, "Added to Home")
                dismiss()
            },
        )
        present(appContext, "Install Assistant", label, "Add it to your home screen?", icon, actions)
    }

    fun showRemoved(context: Context, pkg: String) {
        val appContext = context.applicationContext
        if (!canDraw(appContext)) return
        val label = AppQueryHelper.lastKnownLabel(appContext, pkg) ?: pkg
        val icon: Drawable? = AppQueryHelper.lastKnownIconFile(appContext, pkg)?.let { file ->
            try {
                BitmapFactory.decodeFile(file.absolutePath)?.let { BitmapDrawable(appContext.resources, it) }
            } catch (_: Exception) {
                null
            }
        }
        val actions = listOf(
            CardAction("Not now", false) {
                dismiss()
            },
            CardAction("Clean up", true) {
                InstallAssistantChannel.deliver("cleanup:$pkg")
                toast(appContext, "Cleaning up shortcuts")
                dismiss()
            },
        )
        present(appContext, "Uninstall Assistant", label, "Clean up its shortcuts?", icon, actions)
    }

    fun dismiss() {
        main.post { removeCard() }
    }

    private fun canDraw(appContext: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(appContext)

    // --- window lifecycle (mirrors AfterCallOverlay) --------------------------

    private fun present(
        appContext: Context,
        assistantName: String,
        title: String,
        subtitle: String,
        icon: Drawable?,
        actions: List<CardAction>,
    ) {
        main.post {
            removeCard()
            appContextRef = appContext

            val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                WindowManager.LayoutParams.FLAG_DIM_BEHIND,
                android.graphics.PixelFormat.TRANSLUCENT,
            ).apply {
                dimAmount = 0.45f
                gravity = Gravity.BOTTOM
            }

            val root = buildRoot(appContext, assistantName, title, subtitle, icon, actions)
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
    }

    private fun removeCard() {
        main.removeCallbacks(autoDismiss)
        unregisterHomeWatcher()
        val v = view ?: return
        try {
            windowManager?.removeView(v)
        } catch (_: IllegalArgumentException) {
        }
        view = null
        windowManager = null
    }

    private class OverlayRoot(
        context: Context,
        private val onBack: () -> Unit,
    ) : FrameLayout(context) {
        override fun dispatchKeyEvent(event: KeyEvent): Boolean {
            if (event.keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) {
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

    private fun buildRoot(
        ctx: Context,
        assistantName: String,
        title: String,
        subtitle: String,
        icon: Drawable?,
        actions: List<CardAction>,
    ): View {
        val root = OverlayRoot(ctx) { dismiss() }.apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            isClickable = true
            setOnClickListener { dismiss() }
        }
        val cardParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
        ).apply {
            gravity = Gravity.BOTTOM
            val side = dp(ctx, 10f)
            setMargins(side, side, side, dp(ctx, 16f))
        }
        root.addView(buildCard(ctx, assistantName, title, subtitle, icon, actions), cardParams)
        return root
    }

    private fun buildCard(
        ctx: Context,
        assistantName: String,
        title: String,
        subtitle: String,
        icon: Drawable?,
        actions: List<CardAction>,
    ): View {
        val pad = dp(ctx, 24f)
        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, dp(ctx, 22f), pad, dp(ctx, 18f))
            background = GradientDrawable().apply {
                cornerRadius = dp(ctx, 26f).toFloat()
                setColor(Color.parseColor(SHEET_BG))
            }
            isClickable = true
        }

        // Assistant header: small mark + label + chevron.
        val header = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        header.addView(assistantMark(ctx))
        header.addView(
            TextView(ctx).apply {
                text = assistantName
                setTextColor(Color.parseColor(TEXT_PRIMARY))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 19f)
                setTypeface(typeface, Typeface.BOLD)
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                setPadding(dp(ctx, 12f), 0, dp(ctx, 10f), 0)
            },
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
        )
        header.addView(chevron(ctx))
        card.addView(header)

        // Content block: large installed/removed app icon + title/subtitle.
        val content = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(ctx, 28f), 0, dp(ctx, 26f))
        }
        val badgeSize = dp(ctx, 76f)
        val badge = FrameLayout(ctx).apply {
            background = GradientDrawable().apply {
                cornerRadius = dp(ctx, 20f).toFloat()
                setColor(Color.parseColor(TILE_BG))
            }
            addView(
                iconView(ctx, icon, dp(ctx, 68f), title),
                FrameLayout.LayoutParams(
                    dp(ctx, 68f),
                    dp(ctx, 68f),
                    Gravity.CENTER,
                ),
            )
        }
        content.addView(badge, LinearLayout.LayoutParams(badgeSize, badgeSize))
        val titles = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(ctx, 22f), 0, 0, 0)
        }
        titles.addView(
            TextView(ctx).apply {
                text = title
                setTextColor(Color.parseColor(TEXT_PRIMARY))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 30f)
                setTypeface(typeface, Typeface.BOLD)
                maxLines = 2
                ellipsize = android.text.TextUtils.TruncateAt.END
                includeFontPadding = false
            },
        )
        titles.addView(
            TextView(ctx).apply {
                text = subtitle
                setTextColor(Color.parseColor(TEXT_SECONDARY))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
                setTypeface(typeface, Typeface.BOLD)
                setPadding(0, dp(ctx, 12f), 0, 0)
            },
        )
        content.addView(
            titles,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
        )
        card.addView(content)

        // Large action buttons.
        val row = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
        actions.forEachIndexed { index, action ->
            if (index > 0) row.addView(spacer(ctx, dp(ctx, 18f)))
            row.addView(actionButton(ctx, action))
        }
        card.addView(row)

        // Don't show again.
        card.addView(dontShowAgainRow(ctx))
        return card
    }

    private fun iconView(ctx: Context, icon: Drawable?, size: Int, brand: String): View {
        if (icon != null) {
            return ImageView(ctx).apply {
                setImageDrawable(icon)
                scaleType = ImageView.ScaleType.FIT_CENTER
                layoutParams = LinearLayout.LayoutParams(size, size)
            }
        }
        // Fallback glyph badge.
        return TextView(ctx).apply {
            text = brand.firstOrNull()?.uppercase() ?: "?"
            gravity = Gravity.CENTER
            setTextColor(Color.parseColor(TEXT_PRIMARY))
            setTextSize(
                TypedValue.COMPLEX_UNIT_SP,
                (size / ctx.resources.displayMetrics.density) * 0.45f,
            )
            background = GradientDrawable().apply {
                cornerRadius = size * 0.22f
                setColor(Color.parseColor(TILE_BG))
            }
            layoutParams = LinearLayout.LayoutParams(size, size)
        }
    }

    private fun actionButton(ctx: Context, action: CardAction): View =
        TextView(ctx).apply {
            text = action.label
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
            setTypeface(typeface, Typeface.BOLD)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            includeFontPadding = false
            background = GradientDrawable().apply {
                cornerRadius = dp(ctx, 22f).toFloat()
                if (action.primary) {
                    orientation = GradientDrawable.Orientation.LEFT_RIGHT
                    colors = intArrayOf(
                        Color.parseColor(PRIMARY_START),
                        Color.parseColor(PRIMARY_END),
                    )
                } else {
                    setColor(Color.parseColor(DISMISS_COLOR))
                }
            }
            isClickable = true
            setOnClickListener { action.onTap() }
            layoutParams = LinearLayout.LayoutParams(0, dp(ctx, 76f), 1f)
        }

    private fun dontShowAgainRow(ctx: Context): View {
        val box = View(ctx).apply {
            background = GradientDrawable().apply {
                cornerRadius = dp(ctx, 6f).toFloat()
                setColor(Color.TRANSPARENT)
                setStroke(dp(ctx, 2f), Color.parseColor(TEXT_SECONDARY))
            }
            layoutParams = LinearLayout.LayoutParams(dp(ctx, 28f), dp(ctx, 28f))
        }
        val label = TextView(ctx).apply {
            text = "Don't show again"
            setTextColor(Color.parseColor(TEXT_SECONDARY))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            setTypeface(typeface, Typeface.BOLD)
            setPadding(dp(ctx, 16f), 0, 0, 0)
        }
        return LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(ctx, 28f), 0, dp(ctx, 4f))
            isClickable = true
            setOnClickListener {
                appContextRef?.let { SmartLauncherApplication.setAssistantEnabled(it, false) }
                InstallAssistantChannel.deliver("disable")
                dismiss()
            }
            addView(box)
            addView(label)
        }
    }

    private fun assistantMark(ctx: Context): View {
        val size = dp(ctx, 36f)
        return TextView(ctx).apply {
            text = "A"
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTypeface(typeface, Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(size, size)
            background = GradientDrawable().apply {
                cornerRadius = dp(ctx, 10f).toFloat()
                orientation = GradientDrawable.Orientation.TL_BR
                colors = intArrayOf(Color.parseColor("#08E08A"), Color.parseColor("#066DFF"))
            }
        }
    }

    private fun chevron(ctx: Context): View {
        val size = dp(ctx, 32f)
        return TextView(ctx).apply {
            text = "›"
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 34f)
            setTypeface(typeface, Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(size, size)
        }
    }

    private fun spacer(ctx: Context, width: Int): View =
        View(ctx).apply { layoutParams = LinearLayout.LayoutParams(width, 1) }

    private fun toast(ctx: Context, message: String) {
        try {
            Toast.makeText(ctx, message, Toast.LENGTH_SHORT).show()
        } catch (_: Exception) {
        }
    }

    private fun dp(ctx: Context, value: Float): Int =
        (value * ctx.resources.displayMetrics.density).toInt()
}
