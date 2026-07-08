package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.R
import kotlin.math.hypot

/// The device-wide App Lock screen, drawn as a system overlay (no Activity, so
/// it works over any locked app regardless of the foreground launcher). It
/// renders a monochrome PIN pad or pattern grid that matches the in-launcher
/// [VaultPinPad]/[VaultPatternLock], verifies natively via [AppLockStore], and
/// offers fingerprint only when the user taps it (never auto-prompted).
object AppLockOverlay {
    private const val TAG = "AppLockWatch"
    private var view: View? = null
    private var windowManager: WindowManager? = null
    private var currentPackage: String? = null

    val isShowing: Boolean get() = view != null
    val showingPackage: String? get() = currentPackage

    fun show(context: Context, pkg: String) {
        // No credential → nothing to verify against; never trap the user.
        if (!AppLockStore.isConfigured(context)) {
            Log.w(TAG, "overlay.show($pkg) aborted: no credential configured")
            return
        }
        if (view != null) {
            if (currentPackage == pkg) return
            dismiss()
        }
        val appContext = context.applicationContext
        val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
            ?: return
        val content = AppLockView(
            appContext,
            pkg = pkg,
            onUnlock = {
                AppLockStore.markUnlocked(pkg)
                dismiss()
            },
            onHome = {
                goHome(appContext)
                dismiss()
            },
        )
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
            // Focusable (no NOT_FOCUSABLE flag) so we can intercept the back key.
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_SECURE,
            PixelFormat.OPAQUE,
        )
        // The lock screen is portrait-only, even when drawn over a landscape app
        // (e.g. a game). Pinning the window orientation keeps the PIN pad upright
        // instead of inheriting the locked app's rotation.
        params.screenOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        try {
            wm.addView(content, params)
            windowManager = wm
            view = content
            currentPackage = pkg
            content.requestFocus()
            Log.i(TAG, "overlay shown over $pkg")
        } catch (e: Exception) {
            Log.w(TAG, "overlay addView failed for $pkg", e)
            view = null
            windowManager = null
            currentPackage = null
        }
    }

    fun dismiss() {
        val v = view ?: return
        try {
            windowManager?.removeView(v)
        } catch (_: Exception) {
        }
        view = null
        windowManager = null
        currentPackage = null
    }

    private fun goHome(context: Context) {
        try {
            context.startActivity(
                Intent(Intent.ACTION_MAIN)
                    .addCategory(Intent.CATEGORY_HOME)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {
        }
    }
}

/// The overlay content: header + PIN pad or pattern grid + optional fingerprint.
@SuppressLint("ViewConstructor")
private class AppLockView(
    context: Context,
    private val pkg: String,
    private val onUnlock: () -> Unit,
    private val onHome: () -> Unit,
) : FrameLayout(context) {

    private val white = Color.WHITE
    private val muted = Color.parseColor("#8E8E93")
    private val surface2 = Color.parseColor("#2A2A2D")

    private val type = AppLockStore.type(context)
    private val isPin = type == AppLockStore.TYPE_PIN

    private val pin = StringBuilder()
    private val dots = mutableListOf<View>()
    private lateinit var errorView: TextView

    init {
        setBackgroundColor(Color.BLACK)
        isFocusableInTouchMode = true
        fitsSystemWindows = true

        val column = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(28), dp(64), dp(28), dp(40))
        }
        addView(
            column,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT, Gravity.CENTER),
        )

        column.addView(spacer(dp(24)))
        column.addView(TextView(context).apply {
            text = "App Locked"
            setTextColor(white)
            textSize = 26f
            gravity = Gravity.CENTER
        })
        column.addView(spacer(dp(16)))
        column.addView(buildAppIcon(context))
        column.addView(TextView(context).apply {
            text = appLabel(context)
            setTextColor(muted)
            textSize = 15f
            gravity = Gravity.CENTER
            setPadding(0, dp(10), 0, dp(20))
        })

        errorView = TextView(context).apply {
            setTextColor(Color.parseColor("#FF5A5F"))
            textSize = 14f
            gravity = Gravity.CENTER
            minHeight = dp(20)
        }
        column.addView(errorView)
        column.addView(spacer(dp(8)))

        if (isPin) {
            column.addView(buildDotsRow(context))
            column.addView(spacer(dp(36)))
            column.addView(buildKeypad(context))
        } else {
            column.addView(PatternView(context) { nodes -> onPattern(nodes) })
        }

        if (!isPin && canUseBiometric(context)) {
            column.addView(spacer(dp(18)))
            column.addView(iconKey(context, R.drawable.ic_app_lock_fingerprint) {
                showBiometric(context)
            })
        }

        setOnKeyListener { _, keyCode, event ->
            if (keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) {
                onHome()
                true
            } else {
                false
            }
        }
    }

    // ---- PIN ----------------------------------------------------------------

    private fun buildDotsRow(context: Context): View {
        val row = LinearLayout(context).apply { gravity = Gravity.CENTER }
        dots.clear()
        for (i in 0 until 4) {
            val dot = View(context)
            val lp = LinearLayout.LayoutParams(dp(14), dp(14))
            lp.setMargins(dp(11), 0, dp(11), 0)
            row.addView(dot, lp)
            dots.add(dot)
        }
        refreshDots()
        return row
    }

    private fun refreshDots() {
        for (i in dots.indices) {
            val filled = i < pin.length
            dots[i].background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                if (filled) setColor(white) else setColor(Color.TRANSPARENT)
                setStroke(dp(2), if (filled) white else muted)
            }
        }
    }

    private fun buildKeypad(context: Context): View {
        val pad = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }
        pad.addView(digitRow(context, listOf("1", "2", "3")))
        pad.addView(spacer(dp(18)))
        pad.addView(digitRow(context, listOf("4", "5", "6")))
        pad.addView(spacer(dp(18)))
        pad.addView(digitRow(context, listOf("7", "8", "9")))
        pad.addView(spacer(dp(18)))
        // Bottom row mirrors the Flutter App Lock PIN pad: fingerprint, 0,
        // backspace. If biometrics are off, keep the slot empty for alignment.
        val bottom = LinearLayout(context).apply { gravity = Gravity.CENTER }
        bottom.addView(
            slot(
                if (canUseBiometric(context)) {
                    iconKey(context, R.drawable.ic_app_lock_fingerprint) {
                        showBiometric(context)
                    }
                } else {
                    blankKey(context)
                },
            ),
        )
        bottom.addView(slot(digitKey(context, "0")))
        bottom.addView(slot(textIconKey(context, "⌫") { onBackspace() }))
        pad.addView(bottom)
        return pad
    }

    private fun digitRow(context: Context, digits: List<String>): View {
        val row = LinearLayout(context).apply { gravity = Gravity.CENTER }
        for (d in digits) row.addView(slot(digitKey(context, d)))
        return row
    }

    private fun slot(child: View): View {
        val wrapper = FrameLayout(context)
        val lp = LinearLayout.LayoutParams(dp(76), dp(76))
        lp.setMargins(dp(14), 0, dp(14), 0)
        wrapper.addView(child, FrameLayout.LayoutParams(dp(76), dp(76)))
        wrapper.layoutParams = lp
        return wrapper
    }

    private fun digitKey(context: Context, digit: String): View =
        TextView(context).apply {
            text = digit
            setTextColor(white)
            textSize = 28f
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(surface2)
            }
            setOnClickListener { onDigit(digit) }
        }

    private fun textIconKey(context: Context, glyph: String, onTap: () -> Unit): View =
        TextView(context).apply {
            text = glyph
            setTextColor(white)
            textSize = 24f
            gravity = Gravity.CENTER
            setOnClickListener { onTap() }
        }

    private fun iconKey(context: Context, iconRes: Int, onTap: () -> Unit): View =
        ImageButton(context).apply {
            setImageResource(iconRes)
            setColorFilter(white)
            scaleType = android.widget.ImageView.ScaleType.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(surface2)
            }
            contentDescription = "Use fingerprint"
            setOnClickListener { onTap() }
        }

    private fun blankKey(context: Context): View = View(context)

    private fun buildAppIcon(context: Context): View =
        FrameLayout(context).apply {
            background = GradientDrawable().apply {
                cornerRadius = dp(18).toFloat()
                setColor(surface2)
            }
            addView(
                ImageView(context).apply {
                    setImageDrawable(appIcon(context))
                    scaleType = ImageView.ScaleType.FIT_CENTER
                    contentDescription = appLabel(context)
                },
                FrameLayout.LayoutParams(dp(48), dp(48), Gravity.CENTER),
            )
            layoutParams = LinearLayout.LayoutParams(dp(72), dp(72))
        }

    private fun onDigit(d: String) {
        if (pin.length >= 4) return
        performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
        pin.append(d)
        errorView.text = ""
        refreshDots()
        if (pin.length == 4) {
            val code = pin.toString()
            post { verify(code) }
        }
    }

    private fun onBackspace() {
        if (pin.isEmpty()) return
        pin.deleteCharAt(pin.length - 1)
        refreshDots()
    }

    // ---- Pattern ------------------------------------------------------------

    private fun onPattern(nodes: List<Int>) {
        if (nodes.size < 4) {
            fail("Connect at least 4 dots")
            return
        }
        verify(nodes.joinToString("-"))
    }

    // ---- shared -------------------------------------------------------------

    private fun verify(code: String) {
        if (AppLockStore.verify(context, code)) {
            onUnlock()
            return
        }
        fail(if (isPin) "Wrong PIN" else "Wrong pattern")
    }

    private fun fail(message: String) {
        performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        pin.setLength(0)
        if (isPin) refreshDots()
        errorView.text = message
    }

    private fun showBiometric(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return
        try {
            context.startActivity(
                Intent(context, AppLockBiometricActivity::class.java)
                    .putExtra(AppLockBiometricActivity.EXTRA_PACKAGE, pkg)
                    .putExtra(AppLockBiometricActivity.EXTRA_LABEL, appLabel(context))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {
            // Fall back to PIN/pattern silently.
        }
    }

    private fun canUseBiometric(context: Context): Boolean =
        AppLockStore.biometricEnabled(context) &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P

    // ---- helpers ------------------------------------------------------------

    private fun appLabel(context: Context): String = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) {
        pkg
    }

    private fun appIcon(context: Context) = try {
        context.packageManager.getApplicationIcon(pkg)
    } catch (_: Exception) {
        context.applicationInfo.loadIcon(context.packageManager)
    }

    private fun spacer(height: Int): View =
        View(context).apply {
            layoutParams = LinearLayout.LayoutParams(1, height)
        }

    private fun dp(v: Int): Int = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP,
        v.toFloat(),
        resources.displayMetrics,
    ).toInt()
}

/// A monochrome 3x3 pattern grid, a 1:1 port of the Dart [VaultPatternLock]:
/// drag across dots to connect them (row-major indices 0..8), auto-adding the
/// node between two on a straight swipe, and reporting the ordered sequence so
/// the joined "0-1-2" string hashes identically on both sides.
@SuppressLint("ViewConstructor")
private class PatternView(
    context: Context,
    private val onComplete: (List<Int>) -> Unit,
) : View(context) {

    private val sizePx = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, 300f, resources.displayMetrics,
    ).toInt()

    private val selected = ArrayList<Int>()
    private var cursorX = 0f
    private var cursorY = 0f
    private var hasCursor = false
    private var locked = false

    private val muted = Color.parseColor("#8E8E93")

    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        strokeWidth = dp(5f)
        strokeCap = Paint.Cap.ROUND
        style = Paint.Style.STROKE
    }

    init {
        layoutParams = LinearLayout.LayoutParams(sizePx, sizePx)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(sizePx, sizePx)
    }

    private fun cell(): Float = sizePx / 3f
    private fun nodeRadius(): Float = sizePx / 16f
    private fun hitRadius(): Float = cell() / 2f * 0.7f

    private fun centerX(index: Int): Float = cell() * (index % 3) + cell() / 2f
    private fun centerY(index: Int): Float = cell() * (index / 3) + cell() / 2f

    private fun nodeAt(x: Float, y: Float): Int? {
        for (i in 0 until 9) {
            if (hypot(x - centerX(i), y - centerY(i)) <= hitRadius()) return i
        }
        return null
    }

    /// Node sitting exactly between [a] and [b] on the grid, if any.
    private fun between(a: Int, b: Int): Int? {
        val ar = a / 3; val ac = a % 3
        val br = b / 3; val bc = b % 3
        val mr = ar + br; val mc = ac + bc
        if (mr % 2 != 0 || mc % 2 != 0) return null
        return (mr / 2) * 3 + (mc / 2)
    }

    private fun addAt(x: Float, y: Float) {
        val node = nodeAt(x, y) ?: return
        if (selected.contains(node)) return
        if (selected.isNotEmpty()) {
            val mid = between(selected.last(), node)
            if (mid != null && !selected.contains(mid)) selected.add(mid)
        }
        selected.add(node)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (locked) return true
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                selected.clear()
                cursorX = event.x; cursorY = event.y; hasCursor = true
                addAt(event.x, event.y)
                invalidate()
            }
            MotionEvent.ACTION_MOVE -> {
                cursorX = event.x; cursorY = event.y; hasCursor = true
                addAt(event.x, event.y)
                invalidate()
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val result = ArrayList(selected)
                hasCursor = false
                locked = true
                invalidate()
                onComplete(result)
                postDelayed({
                    selected.clear()
                    locked = false
                    invalidate()
                }, 350)
            }
        }
        return true
    }

    override fun onDraw(canvas: Canvas) {
        for (i in 0 until selected.size - 1) {
            canvas.drawLine(
                centerX(selected[i]), centerY(selected[i]),
                centerX(selected[i + 1]), centerY(selected[i + 1]),
                linePaint,
            )
        }
        if (selected.isNotEmpty() && hasCursor) {
            canvas.drawLine(
                centerX(selected.last()), centerY(selected.last()),
                cursorX, cursorY, linePaint,
            )
        }
        for (i in 0 until 9) {
            val on = selected.contains(i)
            val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = if (on) Color.WHITE else muted
                strokeWidth = dp(2f)
                style = Paint.Style.STROKE
            }
            canvas.drawCircle(centerX(i), centerY(i), nodeRadius(), ring)
            if (on) {
                canvas.drawCircle(
                    centerX(i), centerY(i), nodeRadius() * 0.42f,
                    Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE },
                )
            }
        }
    }

    private fun dp(v: Float): Float = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v, resources.displayMetrics,
    )
}
