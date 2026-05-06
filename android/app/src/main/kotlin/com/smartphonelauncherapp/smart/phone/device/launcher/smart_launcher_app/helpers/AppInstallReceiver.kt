package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.helpers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AppInstallReceiver(
    private val onChanged: (packageName: String, eventType: String) -> Unit
) : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val pkg = intent.data?.schemeSpecificPart ?: return
        when (intent.action) {
            Intent.ACTION_PACKAGE_ADDED -> onChanged(pkg, "added")
            Intent.ACTION_PACKAGE_REMOVED -> onChanged(pkg, "removed")
            Intent.ACTION_PACKAGE_CHANGED -> onChanged(pkg, "changed")
        }
    }
}
