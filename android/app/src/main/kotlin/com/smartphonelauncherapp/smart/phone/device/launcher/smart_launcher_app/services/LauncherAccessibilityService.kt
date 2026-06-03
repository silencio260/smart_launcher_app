package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.view.accessibility.AccessibilityEvent

/**
 * Thin accessibility service that exists ONLY to perform global gesture actions
 * the launcher offers (sleep screen / recents) via [performGlobalAction].
 *
 * App Lock no longer relies on this service: device-wide enforcement moved to
 * [AppLockWatcherService] (Usage-access polling) plus an instant in-launcher
 * overlay, so a user can lock apps without ever enabling accessibility. This
 * service stays opt-in for the gesture features that genuinely need it.
 */
class LauncherAccessibilityService : AccessibilityService() {

    companion object {
        var instance: LauncherAccessibilityService? = null

        fun performAction(action: Int): Boolean =
            instance?.performGlobalAction(action) ?: false

        /** Kept for source compatibility with older callers; now a no-op. */
        fun reloadPolicy(context: Context) {
        }
    }

    override fun onServiceConnected() {
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No app-lock work here anymore; the service only provides global actions.
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }
}
