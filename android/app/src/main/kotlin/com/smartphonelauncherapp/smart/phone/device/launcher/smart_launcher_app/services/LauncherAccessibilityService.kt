package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AppLockGateActivity

class LauncherAccessibilityService : AccessibilityService() {

    companion object {
        private const val PREFS = "app_lock_policy"
        private const val KEY_LOCKED_PACKAGES = "locked_packages"
        var instance: LauncherAccessibilityService? = null
        private var lockedPackages: Set<String> = emptySet()
        private var lastPackage: String? = null
        private var lastGateAt = 0L

        fun performAction(action: Int): Boolean = instance?.performGlobalAction(action) ?: false

        fun reloadPolicy(context: Context) {
            lockedPackages = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getStringSet(KEY_LOCKED_PACKAGES, emptySet())
                ?.toSet()
                ?: emptySet()
        }
    }

    override fun onServiceConnected() {
        instance = this
        reloadPolicy(this)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return
        if (!lockedPackages.contains(pkg)) return
        val now = System.currentTimeMillis()
        if (pkg == lastPackage && now - lastGateAt < 2500) return
        lastPackage = pkg
        lastGateAt = now
        try {
            startActivity(
                Intent(this, AppLockGateActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    .putExtra(AppLockGateActivity.EXTRA_PACKAGE, pkg)
            )
        } catch (_: Exception) {
        }
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }
}
