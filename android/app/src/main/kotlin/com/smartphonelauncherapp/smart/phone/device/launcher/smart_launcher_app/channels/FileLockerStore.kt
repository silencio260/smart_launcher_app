package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.util.Log
import android.util.Size
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.security.SecureRandom

/**
 * Hides vault files and tracks their metadata. Only needs a [Context], so it is
 * shared between [FileLockerChannel] (list/export/delete/thumbnail/view) and
 * [com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.FileImportActivity]
 * (the standalone picker that performs imports/exports).
 *
 * This is a **move-only hide, not encryption** (a deliberate product choice for
 * speed). Importing simply copies the original bytes, untouched, into
 * app-private storage under a neutral `<id>.dat` name — invisible to the gallery
 * / MediaStore / other apps without root. The real name/type lives only in the
 * index (the metadata JSON). A small JPEG preview (`<id>.thumb`) is generated at
 * import time so the grid shows thumbnails, and viewing reads the stored file
 * directly (no decrypt, no copy). Protection against someone who *has* rooted
 * the device is intentionally minimal: the neutral filename, nothing more.
 */
class FileLockerStore(private val context: Context) {
    companion object {
        private const val TAG = "FileLockerStore"
        private const val PREFS = "file_locker_v1"
        private const val META = "files"
        private const val THUMB_TARGET = 512
        private const val VIEW_CACHE_DIR = "vault_view"
        // Storage format marker. Items written by the old AES build lack this and
        // are treated as unreadable (clean slate) so they degrade gracefully.
        private const val FMT = "raw1"
    }

    /** Copies the document at [uri] into the vault and records its metadata. */
    fun importUri(uri: Uri): Map<String, Any?>? {
        val info = queryInfo(uri)
        val mime = context.contentResolver.getType(uri)
        val kind = kindFor(mime, info.first)
        val id = "file_${System.currentTimeMillis()}_${SecureRandom().nextInt(100000)}"
        val vaultFile = File(vaultDir(), "$id.dat")
        context.contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(vaultFile).use { output -> input.copyTo(output) }
        } ?: return null
        val createdAt = System.currentTimeMillis()

        val meta = readMeta()
        meta.put(
            JSONObject()
                .put("id", id)
                .put("name", info.first)
                .put("size", info.second)
                .put("path", vaultFile.absolutePath)
                .put("mime", mime ?: "")
                .put("kind", kind)
                .put("fmt", FMT)
                .put("createdAt", createdAt)
        )
        writeMeta(meta)

        // Best-effort preview: prefer the system's cached thumbnail of the source
        // (instant, no full-file decode), and fall back to decoding our own copy.
        val thumb = thumbnailFromUri(uri)
        if (thumb != null) writeThumb(id, thumb) else generateThumbnail(id)

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
        if (meta.optString("fmt") != FMT) return false
        val source = File(meta.optString("path"))
        if (!source.exists()) return false
        context.contentResolver.openOutputStream(uri)?.use { output ->
            FileInputStream(source).use { input -> input.copyTo(output) }
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

    /**
     * JPEG preview bytes for [id]. If no thumbnail exists yet (an older import,
     * or one whose preview failed to generate) it is built on demand from the
     * stored file and cached, so the grid is self-healing. Returns null for
     * files we can't preview (documents) and for legacy/unreadable items.
     */
    fun thumbnailBytes(id: String): ByteArray? {
        val thumb = File(vaultDir(), "$id.thumb")
        if (thumb.exists()) {
            try {
                return thumb.readBytes()
            } catch (e: Exception) {
                Log.w(TAG, "Stored thumbnail unreadable for $id; regenerating", e)
                thumb.delete()
            }
        }
        return generateThumbnail(id)
    }

    /**
     * Returns the path the viewer should read for [id]. Because the bytes are
     * stored untouched, this is just the stored file itself — no decrypt, no
     * copy. Returns null for legacy/unreadable items or missing files. The name
     * is kept (it used to decrypt to cache) so the Dart channel is unchanged.
     */
    fun decryptToCacheFile(id: String): String? {
        val meta = findMeta(id) ?: return null
        if (meta.optString("fmt") != FMT) return null
        val source = File(meta.optString("path"))
        if (!source.exists()) return null
        return source.absolutePath
    }

    /** Removes any leftover decrypted/preview temp files. Called on re-lock. */
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

    /** Fast system-provided thumbnail of [uri] (API 29+), or null. */
    @SuppressLint("NewApi")
    private fun thumbnailFromUri(uri: Uri): ByteArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return try {
            val bitmap =
                context.contentResolver.loadThumbnail(uri, Size(THUMB_TARGET, THUMB_TARGET), null)
            compress(scaled(bitmap, THUMB_TARGET))
        } catch (e: Exception) {
            Log.w(TAG, "loadThumbnail failed for $uri; will decode from stored copy", e)
            null
        }
    }

    /**
     * Builds and caches the thumbnail for [id] from its stored file, returning
     * the preview bytes (or null if it can't be previewed). Used as the fallback
     * at import and lazily by [thumbnailBytes].
     */
    private fun generateThumbnail(id: String): ByteArray? {
        val meta = findMeta(id) ?: return null
        if (meta.optString("fmt") != FMT) return null
        val source = File(meta.optString("path"))
        if (!source.exists()) return null
        val bytes = try {
            when (meta.optString("kind").ifEmpty { "file" }) {
                "image" -> decodeImageThumbnail(source.readBytes())
                "video" -> videoThumbnailFromFile(source)
                else -> null
            }
        } catch (e: Exception) {
            Log.w(TAG, "Thumbnail generation failed for $id", e)
            null
        } ?: return null
        writeThumb(id, bytes)
        return bytes
    }

    private fun writeThumb(id: String, bytes: ByteArray) {
        try {
            FileOutputStream(File(vaultDir(), "$id.thumb")).use { it.write(bytes) }
        } catch (e: Exception) {
            Log.w(TAG, "Could not cache thumbnail for $id", e)
        }
    }

    /** Decodes [data] (a full image) into a small JPEG preview. */
    @SuppressLint("NewApi")
    private fun decodeImageThumbnail(data: ByteArray): ByteArray? {
        // ImageDecoder (API 28+) handles JPEG/PNG/WebP/HEIC/GIF and applies EXIF
        // orientation; it is far more reliable than BitmapFactory.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                val src = ImageDecoder.createSource(ByteBuffer.wrap(data))
                val bitmap = ImageDecoder.decodeBitmap(src) { decoder, info, _ ->
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    decoder.isMutableRequired = false
                    val longest = maxOf(info.size.width, info.size.height)
                    if (longest > THUMB_TARGET) {
                        val ratio = THUMB_TARGET.toFloat() / longest
                        decoder.setTargetSize(
                            (info.size.width * ratio).toInt().coerceAtLeast(1),
                            (info.size.height * ratio).toInt().coerceAtLeast(1),
                        )
                    }
                }
                return compress(bitmap)
            } catch (e: Exception) {
                Log.w(TAG, "ImageDecoder failed; falling back to BitmapFactory", e)
            }
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        while (longest / sample > THUMB_TARGET * 2) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size, opts) ?: return null
        return compress(scaled(bitmap, THUMB_TARGET))
    }

    private fun videoThumbnailFromFile(source: File): ByteArray? {
        // The stored file is the untouched video, so point the retriever straight
        // at it — no temp file, no decrypt.
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(source.absolutePath)
            val frame = retriever.frameAtTime ?: return null
            compress(scaled(frame, THUMB_TARGET))
        } catch (e: Exception) {
            Log.w(TAG, "Video thumbnail failed", e)
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

    // ---- Storage ------------------------------------------------------------

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
}
