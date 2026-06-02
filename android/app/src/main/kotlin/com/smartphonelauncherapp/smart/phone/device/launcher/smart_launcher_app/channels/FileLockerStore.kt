package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.CipherInputStream
import javax.crypto.CipherOutputStream
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Encrypts/decrypts vault files and tracks their metadata. Only needs a
 * [Context], so it is shared between [FileLockerChannel] (list/export/delete)
 * and [com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.FileImportActivity]
 * (the standalone picker that performs imports/exports).
 */
class FileLockerStore(private val context: Context) {
    companion object {
        private const val PREFS = "file_locker_v1"
        private const val META = "files"
        private const val KEY_ALIAS = "smart_launcher_file_locker_key"
    }

    /** Encrypts the document at [uri] into the vault and records its metadata. */
    fun importUri(uri: Uri): Map<String, Any?>? {
        val info = queryInfo(uri)
        val id = "file_${System.currentTimeMillis()}_${SecureRandom().nextInt(100000)}"
        val vaultFile = File(vaultDir(), "$id.bin")
        context.contentResolver.openInputStream(uri)?.use { input ->
            encryptToFile(input, vaultFile)
        } ?: return null
        val createdAt = System.currentTimeMillis()

        val meta = readMeta()
        meta.put(
            JSONObject()
                .put("id", id)
                .put("name", info.first)
                .put("size", info.second)
                .put("path", vaultFile.absolutePath)
                .put("createdAt", createdAt)
        )
        writeMeta(meta)
        return mapOf(
            "id" to id,
            "name" to info.first,
            "size" to info.second,
            "createdAt" to createdAt,
        )
    }

    fun exportToUri(id: String, uri: Uri): Boolean {
        val meta = findMeta(id) ?: return false
        val source = File(meta.optString("path"))
        if (!source.exists()) return false
        context.contentResolver.openOutputStream(uri)?.use { output ->
            decryptToStream(source, output)
        } ?: return false
        return true
    }

    fun deleteFile(id: String?): Boolean {
        if (id == null) return false
        val meta = readMeta()
        val next = JSONArray()
        var deleted = false
        for (i in 0 until meta.length()) {
            val item = meta.getJSONObject(i)
            if (item.optString("id") == id) {
                File(item.optString("path")).delete()
                deleted = true
            } else {
                next.put(item)
            }
        }
        if (deleted) writeMeta(next)
        return deleted
    }

    fun listFiles(): List<Map<String, Any?>> {
        val meta = readMeta()
        val result = mutableListOf<Map<String, Any?>>()
        for (i in 0 until meta.length()) {
            val item = meta.getJSONObject(i)
            result.add(
                mapOf(
                    "id" to item.optString("id"),
                    "name" to item.optString("name"),
                    "size" to item.optLong("size"),
                    "createdAt" to item.optLong("createdAt"),
                )
            )
        }
        return result
    }

    fun findMeta(id: String): JSONObject? {
        val meta = readMeta()
        for (i in 0 until meta.length()) {
            val item = meta.getJSONObject(i)
            if (item.optString("id") == id) return item
        }
        return null
    }

    private fun queryInfo(uri: Uri): Pair<String, Long> {
        var name = "Locked file"
        var size = 0L
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameIndex >= 0) name = cursor.getString(nameIndex) ?: name
                if (sizeIndex >= 0) size = cursor.getLong(sizeIndex)
            }
        }
        return Pair(name, size)
    }

    private fun vaultDir(): File {
        val dir = File(context.filesDir, "file_locker")
        dir.mkdirs()
        return dir
    }

    private fun readMeta(): JSONArray {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(META, "[]")
        return JSONArray(raw ?: "[]")
    }

    private fun writeMeta(meta: JSONArray) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(META, meta.toString())
            .apply()
    }

    private fun secretKey(): SecretKey {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            throw IllegalStateException("File locker requires Android 6.0+")
        }
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
        if (existing != null) return existing.secretKey

        val keyGenerator =
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .build()
        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }

    private fun encryptToFile(input: java.io.InputStream, file: File) {
        val iv = ByteArray(12)
        SecureRandom().nextBytes(iv)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
        FileOutputStream(file).use { fileOut ->
            fileOut.write(iv)
            CipherOutputStream(fileOut, cipher).use { cipherOut ->
                input.copyTo(cipherOut)
            }
        }
    }

    private fun decryptToStream(file: File, output: java.io.OutputStream) {
        FileInputStream(file).use { fileIn ->
            val iv = ByteArray(12)
            if (fileIn.read(iv) != iv.size) throw IllegalStateException("Bad vault file")
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
            CipherInputStream(fileIn, cipher).use { cipherIn ->
                cipherIn.copyTo(output)
            }
        }
    }
}
