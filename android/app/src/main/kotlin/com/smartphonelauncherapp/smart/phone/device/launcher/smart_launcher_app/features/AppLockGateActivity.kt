package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class AppLockGateActivity : Activity() {
    companion object {
        const val EXTRA_PACKAGE = "locked_package"
        private const val REQUEST_UNLOCK = 9110
    }

    private var packageNameToUnlock: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        packageNameToUnlock = intent.getStringExtra(EXTRA_PACKAGE) ?: ""
        buildUi()
        authenticate()
    }

    private fun buildUi() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
            setBackgroundColor(Color.BLACK)
        }
        root.addView(
            TextView(this).apply {
                text = "App Locked"
                setTextColor(Color.WHITE)
                textSize = 34f
                gravity = Gravity.CENTER
            },
        )
        root.addView(
            TextView(this).apply {
                text = packageNameToUnlock
                setTextColor(Color.rgb(142, 142, 147))
                textSize = 14f
                gravity = Gravity.CENTER
                setPadding(0, 12, 0, 32)
            },
        )
        root.addView(
            Button(this).apply {
                text = "Unlock"
                setOnClickListener { authenticate() }
            },
        )
        setContentView(root)
    }

    private fun authenticate() {
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (keyguard == null || !keyguard.isKeyguardSecure) {
            finish()
            return
        }
        val intent = keyguard.createConfirmDeviceCredentialIntent(
            "Unlock app",
            "Confirm your device lock to continue",
        )
        if (intent == null) {
            finish()
            return
        }
        try {
            startActivityForResult(intent, REQUEST_UNLOCK)
        } catch (_: Exception) {
            finish()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_UNLOCK && resultCode == RESULT_OK) {
            finish()
        } else if (requestCode == REQUEST_UNLOCK) {
            moveTaskToBack(true)
            finish()
        }
    }
}
