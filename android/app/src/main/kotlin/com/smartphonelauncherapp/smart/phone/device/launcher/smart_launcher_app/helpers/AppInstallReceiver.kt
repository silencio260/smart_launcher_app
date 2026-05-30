package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.helpers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AppInstallReceiver(
    private val onChanged: (packageName: String, eventType: String) -> Unit
) : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val pkg = intent.data?.schemeSpecificPart ?: return
        // An app update arrives as REMOVED -> ADDED, both with EXTRA_REPLACING=true.
        // Emit a distinct "updated" event so listeners can refresh the icon without
        // treating it as a real install/uninstall (which would wipe the user's layout).
        val replacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
        when (intent.action) {
            Intent.ACTION_PACKAGE_ADDED -> onChanged(pkg, if (replacing) "updated" else "added")
            Intent.ACTION_PACKAGE_REMOVED -> onChanged(pkg, if (replacing) "updated" else "removed")
            Intent.ACTION_PACKAGE_CHANGED -> onChanged(pkg, "changed")
        }
    }
}
