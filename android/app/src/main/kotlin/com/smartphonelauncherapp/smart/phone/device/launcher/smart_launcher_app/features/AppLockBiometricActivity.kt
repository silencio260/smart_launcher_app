package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features

import android.app.Activity
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal

class AppLockBiometricActivity : Activity() {
    companion object {
        const val EXTRA_PACKAGE = "packageName"
        const val EXTRA_LABEL = "label"
    }

    private var cancellationSignal: CancellationSignal? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            finish()
            return
        }

        val pkg = intent.getStringExtra(EXTRA_PACKAGE)
        if (pkg.isNullOrEmpty()) {
            finish()
            return
        }

        val label = intent.getStringExtra(EXTRA_LABEL) ?: "Locked app"
        val signal = CancellationSignal()
        cancellationSignal = signal
        try {
            val prompt = BiometricPrompt.Builder(this)
                .setTitle("Unlock app")
                .setDescription(label)
                .setNegativeButton("Use PIN", mainExecutor) { _, _ -> finish() }
                .build()
            prompt.authenticate(
                signal,
                mainExecutor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(
                        result: BiometricPrompt.AuthenticationResult,
                    ) {
                        AppLockStore.markUnlocked(pkg)
                        AppLockOverlay.dismiss()
                        finish()
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        finish()
                    }
                },
            )
        } catch (_: Exception) {
            finish()
        }
    }

    override fun onDestroy() {
        cancellationSignal?.cancel()
        cancellationSignal = null
        super.onDestroy()
    }
}
