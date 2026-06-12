package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.overlay.AfterCallOverlay
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.receivers.AfterCallReceiver
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the after-call feature to Dart.
 *
 *  - `setEnabled(enabled)` flips the manifest [AfterCallReceiver] component on/off,
 *    so the call listener exists only while the user has the feature turned on.
 *  - `isEnabled()` reports that component state.
 *  - `consumePendingAction()` lets Dart pull the action chosen on the overlay.
 *
 * An overlay tap always brings the app to the foreground, so [deliver] just
 * stashes the action and the Dart side pulls it on launch/resume — no race with
 * a cold start, and stale actions can't misfire.
 */
class AfterCallChannel(private val context: Context) {

    fun register(messenger: BinaryMessenger) {
        if (!FEATURE_ENABLED) {
            setReceiverEnabled(false)
        }
        MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        val requested = call.argument<Boolean>("enabled") ?: false
                        setReceiverEnabled(FEATURE_ENABLED && requested)
                        result.success(true)
                    }
                    "isEnabled" -> result.success(FEATURE_ENABLED && isReceiverEnabled())
                    // Debug-only: raise the card now, with no real call. Lets the
                    // feature be tested without dialing. Honors the overlay grant
                    // exactly as a real call would.
                    "showOverlayNow" -> {
                        if (FEATURE_ENABLED) {
                            AfterCallOverlay.show(context)
                        }
                        result.success(true)
                    }
                    "consumePendingAction" -> {
                        val action = if (FEATURE_ENABLED) pendingAction else null
                        pendingAction = null
                        result.success(action)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun receiverComponent() =
        ComponentName(context, AfterCallReceiver::class.java)

    private fun setReceiverEnabled(enabled: Boolean) {
        val state = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        context.packageManager.setComponentEnabledSetting(
            receiverComponent(),
            state,
            PackageManager.DONT_KILL_APP,
        )
    }

    private fun isReceiverEnabled(): Boolean =
        context.packageManager.getComponentEnabledSetting(receiverComponent()) ==
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED

    companion object {
        private const val CHANNEL = "com.genrevibes.smartlauncher/after_call"

        // TEMP: after-call is disabled while the feature is paused. Flip back
        // to true to re-enable the receiver, debug card, and pending actions.
        private const val FEATURE_ENABLED = false

        @Volatile
        private var pendingAction: String? = null

        /** Stash an overlay action; Dart pulls it via consumePendingAction(). */
        fun deliver(action: String?) {
            if (!FEATURE_ENABLED) return
            if (action.isNullOrEmpty()) return
            pendingAction = action
        }
    }
}
