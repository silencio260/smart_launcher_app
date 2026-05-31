package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class SecurityChannel(private val activity: Activity) {
    companion object {
        const val REQUEST_AUTH = 7010
        private const val PREFS = "feature_hive_key"
        private const val KEY_WRAPPED = "wrapped"
        private const val KEY_ALIAS = "smart_launcher_hive_key_wrapper"
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
                    "getHiveAesKey" -> result.success(getHiveAesKey())
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

    private fun getHiveAesKey(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val wrapped = prefs.getString(KEY_WRAPPED, null)
        if (wrapped != null) {
            val decoded = Base64.decode(wrapped, Base64.NO_WRAP)
            if (decoded.size > 12) {
                val iv = decoded.copyOfRange(0, 12)
                val cipherText = decoded.copyOfRange(12, decoded.size)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
                val plain = cipher.doFinal(cipherText)
                return Base64.encodeToString(plain, Base64.NO_WRAP)
            }
        }

        val raw = ByteArray(32)
        SecureRandom().nextBytes(raw)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val encrypted = cipher.doFinal(raw)
        val payload = cipher.iv + encrypted
        prefs.edit()
            .putString(KEY_WRAPPED, Base64.encodeToString(payload, Base64.NO_WRAP))
            .apply()
        return Base64.encodeToString(raw, Base64.NO_WRAP)
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
        if (existing != null) return existing.secretKey

        val generator =
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }
}
