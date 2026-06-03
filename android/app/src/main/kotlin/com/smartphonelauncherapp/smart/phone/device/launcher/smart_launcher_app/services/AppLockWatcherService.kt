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
        private const val CHANNEL_ID = "app_lock_guard"
        private const val NOTIF_ID = 7012
        private const val POLL_INTERVAL_MS = 250L

        // Transient system windows that aren't a real "app switch" — leaving to
        // these (e.g. the notification shade) must not re-lock the app.
        private val IGNORED = setOf("com.android.systemui")

        /**
         * Starts the watcher when App Lock is configured and at least one app is
         * locked; otherwise stops it. Safe to call repeatedly (idempotent) and
         * from anywhere with a foreground context (app launch, boot, settings).
         */
        fun syncFromPolicy(context: Context) {
            val shouldRun = AppLockStore.isConfigured(context) &&
                AppLockStore.lockedPackages(context).isNotEmpty()
            val intent = Intent(context, AppLockWatcherService::class.java)
            if (shouldRun) {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                } catch (_: Exception) {
                }
            } else {
                try {
                    context.stopService(intent)
                } catch (_: Exception) {
                }
            }
        }
    }

    private var pollThread: HandlerThread? = null
    private var pollHandler: Handler? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var usageStats: UsageStatsManager? = null

    /// Cursor into the usage-event stream; each tick queries [lastQuery, now].
    private var lastQuery = System.currentTimeMillis()

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
        if (pm == null || pm.isInteractive) startPolling()
        return START_STICKY
    }

    private fun startForegroundCompat() {
        // 2-arg form: the system associates the manifest-declared
        // foregroundServiceType ("specialUse"), so we avoid the API-34-only
        // FOREGROUND_SERVICE_TYPE_SPECIAL_USE constant.
        try {
            startForeground(NOTIF_ID, buildNotification())
        } catch (_: Exception) {
        }
    }

    private fun startPolling() {
        if (polling) return
        polling = true
        // Look back slightly so the app that was already foreground (e.g. right
        // after unlocking the device over a locked app) is caught immediately.
        lastQuery = System.currentTimeMillis() - 1500
        lastForeground = null
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
        val events = u.queryEvents(lastQuery, now)
        lastQuery = now
        var latest: String? = null
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            // MOVE_TO_FOREGROUND (== ACTIVITY_RESUMED on API 29+, same value).
            if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                latest = event.packageName
            }
        }
        if (latest != null) handleForeground(latest)
    }

    private fun handleForeground(pkg: String) {
        if (pkg.isEmpty() || IGNORED.contains(pkg)) return

        // Re-lock whatever we just left, then remember the new foreground.
        val prev = lastForeground
        if (prev != null && prev != pkg && AppLockStore.isUnlocked(prev)) {
            AppLockStore.relock(prev)
        }
        lastForeground = pkg

        if (pkg == packageName) return
        if (!AppLockStore.isLocked(this, pkg)) return
        if (AppLockStore.isUnlocked(pkg)) return

        val now = System.currentTimeMillis()
        if (pkg == lastGatedPackage && now - lastGateAt < 1500 && AppLockOverlay.isShowing) {
            return
        }
        lastGatedPackage = pkg
        lastGateAt = now
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
            .setSmallIcon(applicationInfo.icon)
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
