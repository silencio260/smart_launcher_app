package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features

import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.MediaStore
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.FileLockerStore

/**
 * Standalone, transparent activity that hosts the system file picker for the
 * vault.
 *
 * The launcher's MainActivity is `singleTask`, which means the Storage Access
 * Framework picker opens in its own task and its result never makes it back to
 * `MainActivity.onActivityResult` — that is why in-channel imports silently
 * failed. This activity uses the default (`standard`) launch mode, so it
 * reliably receives `onActivityResult`, performs the encrypt-to-vault work
 * itself, and finishes. Flutter then reconciles the imported files via the
 * `listFiles` channel call once it regains focus.
 *
 * When [EXTRA_DELETE_ORIGINALS] is set, after a successful import it asks the
 * system to delete the source files from the gallery (a true "hide"). On
 * Android 11+ this shows a single system confirmation dialog; the app can't
 * bypass it.
 */
class FileImportActivity : Activity() {
    companion object {
        const val EXTRA_MODE = "mode"
        const val MODE_IMPORT = "import"
        const val MODE_EXPORT = "export"
        const val EXTRA_ID = "id"
        const val EXTRA_NAME = "name"
        const val EXTRA_DELETE_ORIGINALS = "deleteOriginals"

        private const val REQ_IMPORT = 9010
        private const val REQ_EXPORT = 9011
        private const val REQ_DELETE = 9012
    }

    private lateinit var store: FileLockerStore
    private var exportId: String? = null
    private var deleteOriginals = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = FileLockerStore(this)
        deleteOriginals = intent.getBooleanExtra(EXTRA_DELETE_ORIGINALS, false)
        // Only launch the picker on a fresh start; on recreation we wait for the
        // pending result instead of opening a second picker.
        if (savedInstanceState != null) return
        when (intent.getStringExtra(EXTRA_MODE)) {
            MODE_EXPORT -> startExport()
            else -> startImport()
        }
    }

    private fun startImport() {
        val pick = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        try {
            startActivityForResult(pick, REQ_IMPORT)
        } catch (e: Exception) {
            finish()
        }
    }

    private fun startExport() {
        val id = intent.getStringExtra(EXTRA_ID)
        if (id == null) {
            finish()
            return
        }
        exportId = id
        val name = intent.getStringExtra(EXTRA_NAME) ?: "locked-file"
        val create = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        try {
            startActivityForResult(create, REQ_EXPORT)
        } catch (e: Exception) {
            finish()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQ_IMPORT -> {
                val imported = if (resultCode == RESULT_OK && data != null) {
                    importFrom(data)
                } else {
                    emptyList()
                }
                if (deleteOriginals && imported.isNotEmpty()) {
                    removeOriginals(imported) // finishes itself (now or after the delete dialog)
                } else {
                    finish()
                }
            }
            REQ_EXPORT -> {
                val id = exportId
                val uri = data?.data
                if (resultCode == RESULT_OK && id != null && uri != null) {
                    try {
                        store.exportToUri(id, uri)
                    } catch (_: Exception) {
                    }
                }
                finish()
            }
            else -> finish() // REQ_DELETE and anything unexpected.
        }
    }

    /** Imports each picked uri; returns the source uris that imported cleanly. */
    private fun importFrom(data: Intent): List<Uri> {
        val uris = mutableListOf<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) {
                uris.add(clip.getItemAt(i).uri)
            }
        } else {
            data.data?.let { uris.add(it) }
        }
        val imported = mutableListOf<Uri>()
        for (uri in uris) {
            try {
                if (store.importUri(uri) != null) imported.add(uri)
            } catch (_: Exception) {
                // Skip files that can't be read; the rest still import.
            }
        }
        return imported
    }

    /**
     * Asks the system to delete the original [uris] now that copies are safely
     * in the vault. On Android 11+ this is a batched, user-confirmed request; on
     * older versions it is a best-effort direct delete.
     */
    private fun removeOriginals(uris: List<Uri>) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val media = uris.mapNotNull { mediaUriFor(it) }
            if (media.isEmpty()) {
                finish()
                return
            }
            try {
                val request = MediaStore.createDeleteRequest(contentResolver, media)
                startIntentSenderForResult(request.intentSender, REQ_DELETE, null, 0, 0, 0)
                return // finish() happens when REQ_DELETE returns.
            } catch (_: Exception) {
                finish()
                return
            }
        }
        // Pre-R: best effort, no system dialog.
        for (uri in uris) {
            try {
                if (DocumentsContract.isDocumentUri(this, uri)) {
                    DocumentsContract.deleteDocument(contentResolver, uri)
                } else {
                    contentResolver.delete(uri, null, null)
                }
            } catch (_: Exception) {
            }
        }
        finish()
    }

    /**
     * Resolves a SAF document uri to its MediaStore uri so it can be passed to
     * [MediaStore.createDeleteRequest]. Returns null for providers we can't map
     * (e.g. a third-party document provider), in which case the original is left
     * in place rather than risking the wrong delete.
     */
    private fun mediaUriFor(uri: Uri): Uri? {
        return try {
            if (uri.authority == MediaStore.AUTHORITY) return uri
            if (!DocumentsContract.isDocumentUri(this, uri)) return null
            val docId = DocumentsContract.getDocumentId(uri)
            val parts = docId.split(":")
            if (parts.size < 2) return null
            val rowId = parts[1].toLongOrNull() ?: return null
            val base = when (parts[0].lowercase()) {
                "image" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                else -> MediaStore.Files.getContentUri("external")
            }
            ContentUris.withAppendedId(base, rowId)
        } catch (_: Exception) {
            null
        }
    }
}
