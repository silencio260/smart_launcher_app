package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.content.Context
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.SmartLauncherApplication
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.overlay.InstallAssistantOverlay
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the Install/Uninstall Assistant to Dart.
 *
 *  - `setEnabled(enabled)` persists the feature flag and (un)registers the
 *    [SmartLauncherApplication] package detector on the live process.
 *  - `isEnabled()` reports the persisted flag.
 *  - `consumePendingAction()` lets Dart pull the action chosen on the overlay.
 *  - `showOverlayNow(packageName, removed)` is debug-only: raise a card on demand.
 *
 * The overlay never bounces through an Activity — its actions (add-to-home, hide,
 * cleanup, disable) are stashed via [deliver] and applied by Dart the next time the
 * launcher resumes. So [pendingAction] is process-static, exactly like the
 * after-call channel's, and there's no cold-start race.
 */
class InstallAssistantChannel(private val context: Context) {

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    SmartLauncherApplication.setAssistantEnabled(context, enabled)
                    result.success(true)
                }
                "isEnabled" -> result.success(SmartLauncherApplication.isAssistantEnabled(context))
                "consumePendingAction" -> {
                    val action = pendingAction
                    pendingAction = null
                    result.success(action)
                }
                "showOverlayNow" -> {
                    val pkg = call.argument<String>("packageName")
                    val removed = call.argument<Boolean>("removed") ?: false
                    if (pkg != null) {
                        if (removed) {
                            InstallAssistantOverlay.showRemoved(context, pkg)
                        } else {
                            InstallAssistantOverlay.showInstalled(context, pkg)
                        }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val CHANNEL = "com.genrevibes.smartlauncher/install_assistant"

        @Volatile
        private var pendingAction: String? = null

        /** Stash an overlay action; Dart pulls it via consumePendingAction(). */
        fun deliver(action: String?) {
            if (action.isNullOrEmpty()) return
            pendingAction = action
        }
    }
}
