package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.content.Intent
import android.content.IntentFilter
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.AppQueryHelper
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.helpers.AppInstallReceiver

class AppInstallEventChannel(private val activity: Activity) {

    private var receiver: AppInstallReceiver? = null

    fun register(messenger: BinaryMessenger) {
        EventChannel(messenger, "com.genrevibes.smartlauncher/app_installs")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    receiver = AppInstallReceiver { pkg, eventType ->
                        // Drop the cached icon so the next getApps pass re-rasterizes.
                        AppQueryHelper.invalidatePackage(pkg)
                        activity.runOnUiThread {
                            events.success(mapOf("packageName" to pkg, "eventType" to eventType))
                        }
                    }
                    val filter = IntentFilter().apply {
                        addAction(Intent.ACTION_PACKAGE_ADDED)
                        addAction(Intent.ACTION_PACKAGE_REMOVED)
                        addAction(Intent.ACTION_PACKAGE_CHANGED)
                        addDataScheme("package")
                    }
                    activity.registerReceiver(receiver, filter)
                }
                override fun onCancel(arguments: Any?) {
                    receiver?.let { activity.unregisterReceiver(it) }
                    receiver = null
                }
            })
    }
}
