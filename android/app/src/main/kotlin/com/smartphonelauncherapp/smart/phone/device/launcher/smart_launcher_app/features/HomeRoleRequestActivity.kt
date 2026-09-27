package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features

import android.app.Activity
import android.app.role.RoleManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import android.util.Log

/**
 * Transparent trampoline that asks for the home role.
 *
 * MainActivity is singleTask with an empty task affinity, so a role request
 * started from it comes back cancelled at once and the system dialog cannot
 * see who called it — the dialog never shows. Started from this
 * standard-launch-mode activity, the request gets a proper caller and result.
 *
 * If the request returns cancelled almost immediately, the dialog was never
 * shown (e.g. Android auto-denies after the user declined twice), so the
 * default-home-app settings page opens instead. Dart re-checks on resume.
 */
class HomeRoleRequestActivity : Activity() {
    companion object {
        private const val TAG = "HomeRoleRequest"
        private const val REQ_HOME_ROLE = 9020

        // A dialog the user actually saw can't be answered faster than this.
        private const val AUTO_DENIED_WITHIN_MS = 600L
    }

    private var requestedAt = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // On recreation the pending result is still delivered; don't re-ask.
        if (savedInstanceState != null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(RoleManager::class.java)
            if (roleManager != null &&
                roleManager.isRoleAvailable(RoleManager.ROLE_HOME) &&
                !roleManager.isRoleHeld(RoleManager.ROLE_HOME)
            ) {
                try {
                    requestedAt = SystemClock.elapsedRealtime()
                    startActivityForResult(
                        roleManager.createRequestRoleIntent(RoleManager.ROLE_HOME),
                        REQ_HOME_ROLE
                    )
                    return
                } catch (e: Exception) {
                    Log.w(TAG, "Role request failed, opening home settings", e)
                }
            }
        }
        openHomeSettingsAndFinish()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_HOME_ROLE) return
        val elapsed = SystemClock.elapsedRealtime() - requestedAt
        Log.i(TAG, "Role request result=$resultCode after ${elapsed}ms")
        if (resultCode != RESULT_OK && elapsed < AUTO_DENIED_WITHIN_MS) {
            openHomeSettingsAndFinish()
        } else {
            finish()
        }
    }

    private fun openHomeSettingsAndFinish() {
        try {
            startActivity(Intent(Settings.ACTION_HOME_SETTINGS))
        } catch (e: Exception) {
            Log.w(TAG, "Home settings unavailable", e)
        }
        finish()
    }
}
