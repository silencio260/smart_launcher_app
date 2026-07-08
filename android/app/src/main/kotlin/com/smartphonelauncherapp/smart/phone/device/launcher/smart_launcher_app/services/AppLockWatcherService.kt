package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.R
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AppLockOverlay
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AppLockStore

/**
 * Device-wide App Lock enforcement WITHOUT an accessibility service.
 *
 * A foreground service polls [UsageStatsManager] (≈[POLL_INTERVAL_MS]) for the
 * current foreground package and draws [AppLockOverlay] over any locked app —
 * exactly what the accessibility service used to do, but driven by the
 * `PACKAGE_USAGE_STATS` (Usage access) permission instead. Trade-off: polling
 * means a locked app can flash for a moment before the lock drops; in exchange
 * App Lock needs no accessibility permission (Play-policy friendly).
 *
 * Battery: we only poll while the screen is interactive and clear all unlock
 * sessions on screen-off (re-lock on leave). The foreground notification is
 * IMPORTANCE_MIN / VISIBILITY_SECRET so it stays out of the user's way.
 */
class AppLockWatcherService : Service() {

    companion object {
        private const val TAG = "AppLockWatch"
        private const val CHANNEL_ID = "app_lock_guard"
        private const val NOTIF_ID = 7012
        private const val POLL_INTERVAL_MS = 250L

        // How far back each poll scans the usage-event stream. UsageStatsManager
        // flushes foreground events with an OEM-dependent delay (often >1s), so we
        // re-scan a trailing window every tick and act on the most recent event
        // rather than a tiny non-overlapping slice — otherwise late-flushed events
        // fall between slices and are missed. handleForeground() is idempotent, so
        // re-seeing the same event is harmless.
        private const val EVENT_LOOKBACK_MS = 8000L

        // Transient system windows that aren't a real "app switch" — leaving to
        // these (e.g. the notification shade) must not re-lock the app.
        private val IGNORED = setOf("com.android.systemui")

        /**
         * Starts the watcher when App Lock is configured and at least one app is
         * locked; otherwise stops it. Safe to call repeatedly (idempotent) and
         * from anywhere with a foreground context (app launch, boot, settings).
         */
        fun syncFromPolicy(context: Context) {
            val configured = AppLockStore.isConfigured(context)
            val lockedCount = AppLockStore.lockedPackages(context).size
            val shouldRun = configured && lockedCount > 0
            Log.i(
                TAG,
                "syncFromPolicy: configured=$configured lockedCount=$lockedCount shouldRun=$shouldRun",
            )
            val intent = Intent(context, AppLockWatcherService::class.java)
            if (shouldRun) {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "syncFromPolicy: failed to start service", e)
                }
            } else {
                try {
                    context.stopService(intent)
                } catch (e: Exception) {
                    Log.w(TAG, "syncFromPolicy: failed to stop service", e)
                }
            }
        }
    }

    private var pollThread: HandlerThread? = null
    private var pollHandler: Handler? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var usageStats: UsageStatsManager? = null

    /// The last real foreground app, used to re-lock on leave.
    private var lastForeground: String? = null
    private var lastGatedPackage: String? = null
    private var lastGateAt = 0L

    @Volatile
    private var polling = false

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> onScreenOff()
                Intent.ACTION_SCREEN_ON, Intent.ACTION_USER_PRESENT -> startPolling()
            }
        }
    }

    private val pollRunnable = object : Runnable {
        override fun run() {
            if (!polling) return
            try {
                pollOnce()
            } catch (_: Exception) {
            }
            pollHandler?.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        usageStats = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
        pollThread = HandlerThread("AppLockWatch").also { it.start() }
        pollHandler = Handler(pollThread!!.looper)
        try {
            registerReceiver(
                screenReceiver,
                IntentFilter().apply {
                    addAction(Intent.ACTION_SCREEN_OFF)
                    addAction(Intent.ACTION_SCREEN_ON)
                    addAction(Intent.ACTION_USER_PRESENT)
                },
            )
        } catch (_: Exception) {
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat()
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
        val interactive = pm == null || pm.isInteractive
        Log.i(TAG, "onStartCommand: interactive=$interactive usageStats=${usageStats != null}")
        if (interactive) startPolling()
        return START_STICKY
    }

    private fun startForegroundCompat() {
        // 2-arg form: the system associates the manifest-declared
        // foregroundServiceType ("specialUse"), so we avoid the API-34-only
        // FOREGROUND_SERVICE_TYPE_SPECIAL_USE constant.
        try {
            startForeground(NOTIF_ID, buildNotification())
        } catch (e: Exception) {
            Log.w(TAG, "startForeground failed", e)
        }
    }

    private fun startPolling() {
        if (polling) return
        polling = true
        lastForeground = null
        Log.i(TAG, "startPolling")
        pollHandler?.removeCallbacks(pollRunnable)
        pollHandler?.post(pollRunnable)
    }

    private fun stopPolling() {
        polling = false
        pollHandler?.removeCallbacks(pollRunnable)
    }

    private fun onScreenOff() {
        stopPolling()
        AppLockStore.clearSession()
        lastForeground = null
        mainHandler.post { AppLockOverlay.dismiss() }
    }

    private fun pollOnce() {
        val u = usageStats ?: return
        val now = System.currentTimeMillis()
        // Scan a trailing window and act on the latest foreground event, so events
        // the system flushes late are still seen (see EVENT_LOOKBACK_MS).
        val events = u.queryEvents(now - EVENT_LOOKBACK_MS, now)
        var latest: String? = null
        var latestTs = 0L
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            // MOVE_TO_FOREGROUND (== ACTIVITY_RESUMED on API 29+, same value).
            if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND &&
                event.timeStamp >= latestTs
            ) {
                latestTs = event.timeStamp
                latest = event.packageName
            }
        }
        if (latest != null) handleForeground(latest)
    }

    private fun handleForeground(pkg: String) {
        if (pkg.isEmpty() || IGNORED.contains(pkg)) return

        val changed = pkg != lastForeground
        if (changed) Log.i(TAG, "foreground=$pkg")

        // The lock screen is a system overlay window, not an Activity, so the
        // Home and Recents buttons can't take it down — pressing Home just leaves
        // it painted over whatever the user navigated to, trapping them on the
        // lock screen. So whenever the foreground is no longer the app we're
        // gating (Home, an app switch, etc.), drop the overlay ourselves.
        // (systemui is filtered out above, so peeking Recents keeps it up.)
        val gating = AppLockOverlay.showingPackage
        if (gating != null && gating != pkg) {
            if (changed) Log.i(TAG, "  left $gating (now $pkg) -> dismissing overlay")
            mainHandler.post { AppLockOverlay.dismiss() }
        }

        // Re-lock whatever we just left, then remember the new foreground.
        val prev = lastForeground
        if (prev != null && prev != pkg && AppLockStore.isUnlocked(prev)) {
            AppLockStore.relock(prev)
        }
        lastForeground = pkg

        if (pkg == packageName) {
            AppLockStore.clearSession()
            return
        }
        if (!AppLockStore.isLocked(this, pkg)) {
            if (changed) Log.i(TAG, "  not locked, skipping")
            return
        }
        if (AppLockStore.isUnlocked(pkg)) {
            if (changed) Log.i(TAG, "  locked but already unlocked this session")
            return
        }

        val now = System.currentTimeMillis()
        if (pkg == lastGatedPackage && now - lastGateAt < 1500 && AppLockOverlay.isShowing) {
            return
        }
        lastGatedPackage = pkg
        lastGateAt = now
        Log.i(TAG, "  gating $pkg -> showing overlay")
        mainHandler.post { AppLockOverlay.show(applicationContext, pkg) }
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "App Lock",
                NotificationManager.IMPORTANCE_MIN,
            ).apply {
                description = "Keeps your locked apps protected"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }
            nm.createNotificationChannel(channel)
        }

        val openIntent = Intent().apply {
            component = ComponentName(packageName, "$packageName.features.AppLockerActivity")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
        val pending = PendingIntent.getActivity(this, 0, openIntent, piFlags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder.setContentTitle("App Lock is on")
            .setContentText("Protecting your locked apps")
            .setSmallIcon(R.drawable.ic_stat_smart_launcher)
            .setOngoing(true)
            .setContentIntent(pending)
            .setCategory(Notification.CATEGORY_SERVICE)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder.setPriority(Notification.PRIORITY_MIN)
        }
        return builder.build()
    }

    override fun onDestroy() {
        stopPolling()
        try {
            unregisterReceiver(screenReceiver)
        } catch (_: Exception) {
        }
        pollThread?.quitSafely()
        pollThread = null
        pollHandler = null
        mainHandler.post { AppLockOverlay.dismiss() }
        super.onDestroy()
    }
}
