package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AppLockOverlay
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AppLockStore
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services.AppLockWatcherService

/// Mirrors the App Lock credential from Dart into native [AppLockStore] so the
/// device-wide lock overlay (which runs with no Flutter engine) can verify it.
/// The hash is computed Dart-side; we just persist what we're handed.
class AppLockChannel(private val context: Context) {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.genrevibes.smartlauncher/app_lock")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAppLockCredential" -> {
                        val type = call.argument<String>("type") ?: AppLockStore.TYPE_PIN
                        val salt = call.argument<String>("salt") ?: ""
                        val hash = call.argument<String>("hash") ?: ""
                        AppLockStore.setCredential(context, type, salt, hash)
                        result.success(true)
                    }
                    "setAppLockBiometricEnabled" -> {
                        AppLockStore.setBiometricEnabled(
                            context,
                            call.argument<Boolean>("enabled") ?: false,
                        )
                        result.success(true)
                    }
                    "showAppLockOverlay" -> {
                        // Instant in-launcher gate: when the launcher itself opens
                        // a locked app, draw the same PIN/pattern overlay the
                        // watcher uses, so the app launches behind it with no
                        // device-credential prompt. Skip if already unlocked this
                        // session so re-launching an open app isn't re-gated.
                        val pkg = call.argument<String>("packageName")
                        if (pkg.isNullOrEmpty() || AppLockStore.isUnlocked(pkg)) {
                            result.success(false)
                        } else {
                            AppLockOverlay.show(context, pkg)
                            result.success(true)
                        }
                    }
                    "clearAppLockCredential" -> {
                        AppLockStore.clearCredential(context)
                        // App Lock is no longer configured → stop the watcher.
                        AppLockWatcherService.syncFromPolicy(context)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
