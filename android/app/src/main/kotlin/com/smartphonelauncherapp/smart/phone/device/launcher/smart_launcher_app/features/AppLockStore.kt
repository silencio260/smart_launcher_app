package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features

import android.content.Context
import java.security.MessageDigest

/// Single source of truth for App Lock, stored in the `app_lock_policy`
/// SharedPreferences (shared with the accessibility service + overlay). It holds
/// the locked package list plus a credential mirrored from the Dart side.
///
/// The credential hash is computed exactly like the Dart `AppLockSecurityRepository`
/// (`sha256("$salt::$code")`, lowercase hex), so a PIN/pattern set in the launcher
/// verifies here even when no Flutter engine is running.
object AppLockStore {
    private const val PREFS = "app_lock_policy"
    private const val KEY_LOCKED = "locked_packages"
    private const val KEY_TYPE = "cred_type"
    private const val KEY_SALT = "cred_salt"
    private const val KEY_HASH = "cred_hash"
    private const val KEY_BIOMETRIC = "biometric_enabled"

    const val TYPE_PIN = "pin"
    const val TYPE_PATTERN = "pattern"

    // Packages unlocked for the current session; cleared when the user leaves a
    // locked app or the screen turns off (re-lock on leave).
    private val unlockedPackages = mutableSetOf<String>()

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // ---- locked apps --------------------------------------------------------

    fun lockedPackages(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_LOCKED, emptySet())?.toSet() ?: emptySet()

    fun isLocked(context: Context, pkg: String): Boolean =
        lockedPackages(context).contains(pkg)

    // ---- credential ---------------------------------------------------------

    fun isConfigured(context: Context): Boolean =
        !prefs(context).getString(KEY_HASH, null).isNullOrEmpty()

    fun type(context: Context): String =
        prefs(context).getString(KEY_TYPE, TYPE_PIN) ?: TYPE_PIN

    fun biometricEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_BIOMETRIC, false)

    fun setCredential(context: Context, type: String, salt: String, hash: String) {
        prefs(context).edit()
            .putString(KEY_TYPE, type)
            .putString(KEY_SALT, salt)
            .putString(KEY_HASH, hash)
            .apply()
    }

    fun setBiometricEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_BIOMETRIC, enabled).apply()
    }

    fun clearCredential(context: Context) {
        prefs(context).edit()
            .remove(KEY_TYPE)
            .remove(KEY_SALT)
            .remove(KEY_HASH)
            .remove(KEY_BIOMETRIC)
            .apply()
        clearSession()
    }

    /// True when [code] matches the stored credential. [code] is a PIN string or
    /// a pattern encoded as node indices joined with '-' (e.g. "0-1-2-4").
    fun verify(context: Context, code: String): Boolean {
        val p = prefs(context)
        val salt = p.getString(KEY_SALT, null) ?: return false
        val hash = p.getString(KEY_HASH, null) ?: return false
        return constantTimeEquals(sha256Hex("$salt::$code"), hash)
    }

    // ---- per-session unlock state ------------------------------------------

    fun isUnlocked(pkg: String): Boolean = unlockedPackages.contains(pkg)

    fun markUnlocked(pkg: String) {
        unlockedPackages.add(pkg)
    }

    fun relock(pkg: String) {
        unlockedPackages.remove(pkg)
    }

    fun clearSession() {
        unlockedPackages.clear()
    }

    // ---- hashing ------------------------------------------------------------

    private fun sha256Hex(input: String): String {
        val bytes = MessageDigest.getInstance("SHA-256")
            .digest(input.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun constantTimeEquals(a: String, b: String): Boolean {
        if (a.length != b.length) return false
        var diff = 0
        for (i in a.indices) diff = diff or (a[i].code xor b[i].code)
        return diff == 0
    }
}
