package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
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
 * [Context], so it is shared between [FileLockerChannel] (list/export/delete/
 * thumbnail/view) and
 * [com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.FileImportActivity]
 * (the standalone picker that performs imports/exports).
 *
 * Every imported file is AES-GCM encrypted into app-private storage (invisible
 * to the gallery / MediaStore / other apps without root). A small JPEG preview
 * is generated at import time and stored *also encrypted* (`<id>.thumb`) so the
 * vault grid can show real thumbnails without decrypting the whole file. To
 * view an item full-screen we decrypt it on demand into a private cache dir that
 * is wiped whenever the vault locks.
 */
class FileLockerStore(private val context: Context) {
    companion object {
        private const val PREFS = "file_locker_v1"
        private const val META = "files"
        private const val KEY_ALIAS = "smart_launcher_file_locker_key"
        private const val THUMB_TARGET = 512
        private const val VIEW_CACHE_DIR = "vault_view"
    }

    /** Encrypts the document at [uri] into the vault and records its metadata. */
    fun importUri(uri: Uri): Map<String, Any?>? {
        val info = queryInfo(uri)
        val mime = context.contentResolver.getType(uri)
        val kind = kindFor(mime, info.first)
        val id = "file_${System.currentTimeMillis()}_${SecureRandom().nextInt(100000)}"
        val vaultFile = File(vaultDir(), "$id.bin")
        context.contentResolver.openInputStream(uri)?.use { input ->
            encryptToFile(input, vaultFile)
        } ?: return null
        val createdAt = System.currentTimeMillis()

        // Best-effort preview; documents (and anything we can't decode) just get
        // a type icon on the Flutter side.
        try {
            val thumb = when (kind) {
                "image" -> imageThumbnail(uri)
                "video" -> videoThumbnail(uri)
                else -> null
            }
            if (thumb != null) {
                encryptToFile(ByteArrayInputStream(thumb), File(vaultDir(), "$id.thumb"))
            }
        } catch (_: Exception) {
        }

        val meta = readMeta()
        meta.put(
            JSONObject()
                .put("id", id)
                .put("name", info.first)
                .put("size", info.second)
                .put("path", vaultFile.absolutePath)
                .put("mime", mime ?: "")
                .put("kind", kind)
                .put("createdAt", createdAt)
        )
        writeMeta(meta)
        return mapOf(
            "id" to id,
            "name" to info.first,
            "size" to info.second,
            "mime" to (mime ?: ""),
            "kind" to kind,
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
                File(vaultDir(), "$id.thumb").delete()
                File(File(context.cacheDir, VIEW_CACHE_DIR), id).delete()
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
                    "mime" to item.optString("mime"),
                    "kind" to (item.optString("kind").ifEmpty { "file" }),
                    "createdAt" to item.optLong("createdAt"),
                )
            )
        }
        return result
    }

    /** Decrypted JPEG preview bytes for [id], or null if there is no preview. */
    fun thumbnailBytes(id: String): ByteArray? {
        val thumb = File(vaultDir(), "$id.thumb")
        if (!thumb.exists()) return null
        return try {
            val out = ByteArrayOutputStream()
            decryptToStream(thumb, out)
            out.toByteArray()
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Decrypts [id] into a private cache file (keeping its extension so players
     * recognise the format) and returns its absolute path, or null on failure.
     * The cache dir is wiped by [clearViewCache] when the vault locks.
     */
    fun decryptToCacheFile(id: String): String? {
        val meta = findMeta(id) ?: return null
        val source = File(meta.optString("path"))
        if (!source.exists()) return null
        val ext = meta.optString("name").substringAfterLast('.', "")
        val dir = File(context.cacheDir, VIEW_CACHE_DIR).apply { mkdirs() }
        val out = File(dir, if (ext.isEmpty()) id else "$id.$ext")
        return try {
            FileOutputStream(out).use { decryptToStream(source, it) }
            out.absolutePath
        } catch (_: Exception) {
            out.delete()
            null
        }
    }

    /** Removes every decrypted preview file. Called when the vault re-locks. */
    fun clearViewCache() {
        File(context.cacheDir, VIEW_CACHE_DIR).deleteRecursively()
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

    private fun kindFor(mime: String?, name: String): String {
        val m = mime?.lowercase()
        if (m != null) {
            if (m.startsWith("image/")) return "image"
            if (m.startsWith("video/")) return "video"
        }
        // Fall back to the file extension when the provider gives no/odd mime.
        val ext = name.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "jpg", "jpeg", "png", "webp", "gif", "bmp", "heic", "heif" -> "image"
            "mp4", "mov", "mkv", "3gp", "webm", "m4v", "avi" -> "video"
            else -> "file"
        }
    }

    // ---- Thumbnails ---------------------------------------------------------

    private fun imageThumbnail(uri: Uri): ByteArray? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, bounds)
        } ?: return null
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        while (longest / sample > THUMB_TARGET * 2) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        val bitmap = context.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, opts)
        } ?: return null
        return compress(scaled(bitmap, THUMB_TARGET))
    }

    private fun videoThumbnail(uri: Uri): ByteArray? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            val frame = retriever.frameAtTime ?: return null
            compress(scaled(frame, THUMB_TARGET))
        } catch (_: Exception) {
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }

    /** Downscales [bitmap] so its longest edge is at most [target] px. */
    private fun scaled(bitmap: Bitmap, target: Int): Bitmap {
        val longest = maxOf(bitmap.width, bitmap.height)
        if (longest <= target) return bitmap
        val ratio = target.toFloat() / longest
        val w = (bitmap.width * ratio).toInt().coerceAtLeast(1)
        val h = (bitmap.height * ratio).toInt().coerceAtLeast(1)
        val out = Bitmap.createScaledBitmap(bitmap, w, h, true)
        if (out != bitmap) bitmap.recycle()
        return out
    }

    private fun compress(bitmap: Bitmap): ByteArray {
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    // ---- Storage / crypto ---------------------------------------------------

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
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        // AndroidKeyStore keys are created with randomized encryption required, so
        // the Keystore MUST generate the GCM IV itself. Supplying our own here
        // throws "Caller-provided IV not permitted" — instead we let init() pick
        // the IV and read it back (always 12 bytes for GCM) to prefix the file.
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val iv = cipher.iv
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
