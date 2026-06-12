package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app

import android.app.Application
import android.content.Context
import android.content.pm.LauncherApps
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.UserHandle
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.overlay.InstallAssistantOverlay

/**
 * Custom Application that hosts the Install/Uninstall Assistant's package detector.
 *
 * Package add/remove broadcasts are NOT exempt from Android O's implicit-broadcast
 * ban, so a manifest receiver (like the after-call one) would never fire on a modern
 * targetSdk. Instead we use [LauncherApps.Callback] — the API built for launchers —
 * registered here at Application scope. It delivers package changes for as long as
 * the launcher *process* is alive, which for a home app is essentially always, so
 * the assistant's overlay can be raised even when the launcher UI isn't on screen
 * (e.g. while the user is in the Play Store).
 *
 * The detector is gated by a persisted flag so it costs nothing while the feature is
 * off; Dart flips it through InstallAssistantChannel.setEnabled.
 */
class SmartLauncherApplication : Application() {

    private var launcherApps: LauncherApps? = null
    private var callback: LauncherApps.Callback? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        instance = this
        if (FEATURE_ENABLED && isAssistantEnabled(this)) register()
    }

    /** Begin listening for package add/remove. Idempotent. */
    fun register() {
        if (!FEATURE_ENABLED) return
        if (callback != null) return
        val apps = getSystemService(Context.LAUNCHER_APPS_SERVICE) as? LauncherApps ?: return
        val cb = object : LauncherApps.Callback() {
            override fun onPackageAdded(packageName: String, user: UserHandle) {
                if (!FEATURE_ENABLED) return
                if (packageName == this@SmartLauncherApplication.packageName) return
                InstallAssistantOverlay.showInstalled(this@SmartLauncherApplication, packageName)
            }

            override fun onPackageRemoved(packageName: String, user: UserHandle) {
                if (!FEATURE_ENABLED) return
                if (packageName == this@SmartLauncherApplication.packageName) return
                // Read last-known label/icon happens inside the overlay; do it before
                // any cache invalidation elsewhere wipes the cached icon file.
                InstallAssistantOverlay.showRemoved(this@SmartLauncherApplication, packageName)
            }

            // A change while updating fires onPackageChanged instead of add/remove —
            // not a real install/uninstall, so ignore it.
            override fun onPackageChanged(packageName: String, user: UserHandle) {}

            override fun onPackagesAvailable(
                packageNames: Array<out String>,
                user: UserHandle,
                replacing: Boolean,
            ) {}

            override fun onPackagesUnavailable(
                packageNames: Array<out String>,
                user: UserHandle,
                replacing: Boolean,
            ) {}
        }
        try {
            apps.registerCallback(cb, handler)
            launcherApps = apps
            callback = cb
        } catch (_: Exception) {
        }
    }

    /** Stop listening. Idempotent. */
    fun unregister() {
        val apps = launcherApps
        val cb = callback
        if (apps != null && cb != null) {
            try {
                apps.unregisterCallback(cb)
            } catch (_: Exception) {
            }
        }
        launcherApps = null
        callback = null
    }

    companion object {
        private const val PREFS = "install_assistant"
        private const val KEY_ENABLED = "enabled"

        // TEMP: Install/Uninstall Assistant is disabled while the feature is
        // paused. Flip back to true to re-enable package detection.
        private const val FEATURE_ENABLED = false

        @Volatile
        var instance: SmartLauncherApplication? = null
            private set

        fun isAssistantEnabled(context: Context): Boolean =
            FEATURE_ENABLED && context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_ENABLED, false)

        fun setAssistantEnabled(context: Context, enabled: Boolean) {
            val shouldEnable = FEATURE_ENABLED && enabled
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_ENABLED, shouldEnable)
                .apply()
            val app = instance
            if (app != null) {
                if (shouldEnable) app.register() else app.unregister()
            }
        }
    }
}
