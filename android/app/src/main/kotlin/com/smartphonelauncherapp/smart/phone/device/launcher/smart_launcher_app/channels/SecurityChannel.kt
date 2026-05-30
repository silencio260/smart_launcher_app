package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class SecurityChannel(private val activity: Activity) {
    companion object {
        const val REQUEST_AUTH = 7010
    }

    private var pendingResult: MethodChannel.Result? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.genrevibes.smartlauncher/security")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "authenticate" -> authenticate(
                        title = call.argument<String>("title") ?: "Unlock",
                        description = call.argument<String>("description") ?: "Confirm your device lock",
                        result = result
                    )
                    else -> result.notImplemented()
                }
            }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_AUTH) return false
        pendingResult?.success(resultCode == Activity.RESULT_OK)
        pendingResult = null
        return true
    }

    private fun authenticate(
        title: String,
        description: String,
        result: MethodChannel.Result,
    ) {
        if (pendingResult != null) {
            result.success(false)
            return
        }
        val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (keyguard == null || !keyguard.isKeyguardSecure) {
            result.success(true)
            return
        }
        val intent: Intent? = keyguard.createConfirmDeviceCredentialIntent(title, description)
        if (intent == null) {
            result.success(false)
            return
        }
        pendingResult = result
        try {
            activity.startActivityForResult(intent, REQUEST_AUTH)
        } catch (e: Exception) {
            pendingResult = null
            result.success(false)
        }
    }
}
