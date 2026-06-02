package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services

import android.accessibilityservice.AccessibilityService
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.view.accessibility.AccessibilityEvent
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AppLockOverlay
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AppLockStore

class LauncherAccessibilityService : AccessibilityService() {

    companion object {
        var instance: LauncherAccessibilityService? = null
        private var lastPackage: String? = null
        private var lastGateAt = 0L

        // Transient system windows that aren't a real "app switch" — leaving to
        // these (e.g. pulling the notification shade) must not re-lock the app.
        private val IGNORED = setOf("com.android.systemui")

        fun performAction(action: Int): Boolean =
            instance?.performGlobalAction(action) ?: false

        // App Lock now reads its policy live from [AppLockStore]; kept so
        // SystemChannel can ping us after the locked-app list changes.
        fun reloadPolicy(context: Context) {
            // No cache to refresh — AppLockStore reads SharedPreferences directly.
        }
    }

    /// The last real foreground app, used to re-lock on leave.
    private var lastForeground: String? = null

    private val screenOffReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_OFF) {
                AppLockStore.clearSession()
                lastForeground = null
                AppLockOverlay.dismiss()
            }
        }
    }

    override fun onServiceConnected() {
        instance = this
        try {
            registerReceiver(screenOffReceiver, IntentFilter(Intent.ACTION_SCREEN_OFF))
        } catch (_: Exception) {
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg.isEmpty() || IGNORED.contains(pkg)) return

        // Re-lock whatever we just left, then remember the new foreground.
        relockLeft(pkg)
        lastForeground = pkg

        // Our own launcher (and anything not locked) needs no gate.
        if (pkg == packageName) return
        if (!AppLockStore.isLocked(this, pkg)) return
        if (AppLockStore.isUnlocked(pkg)) return

        val now = System.currentTimeMillis()
        if (pkg == lastPackage && now - lastGateAt < 1500 && AppLockOverlay.isShowing) {
            return
        }
        lastPackage = pkg
        lastGateAt = now
        AppLockOverlay.show(this, pkg)
    }

    /// When the foreground moves away from a locked app the user had unlocked,
    /// re-lock it so re-opening prompts again ("re-lock on leave").
    private fun relockLeft(newPkg: String) {
        val prev = lastForeground
        if (prev != null && prev != newPkg && AppLockStore.isUnlocked(prev)) {
            AppLockStore.relock(prev)
        }
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        try {
            unregisterReceiver(screenOffReceiver)
        } catch (_: Exception) {
        }
        AppLockOverlay.dismiss()
        instance = null
        super.onDestroy()
    }
}
