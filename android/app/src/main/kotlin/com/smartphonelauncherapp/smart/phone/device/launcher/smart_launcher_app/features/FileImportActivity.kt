package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
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
 */
class FileImportActivity : Activity() {
    companion object {
        const val EXTRA_MODE = "mode"
        const val MODE_IMPORT = "import"
        const val MODE_EXPORT = "export"
        const val EXTRA_ID = "id"
        const val EXTRA_NAME = "name"

        private const val REQ_IMPORT = 9010
        private const val REQ_EXPORT = 9011
    }

    private lateinit var store: FileLockerStore
    private var exportId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = FileLockerStore(this)
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
        if (resultCode == RESULT_OK && data != null) {
            when (requestCode) {
                REQ_IMPORT -> importFrom(data)
                REQ_EXPORT -> {
                    val id = exportId
                    val uri = data.data
                    if (id != null && uri != null) {
                        try {
                            store.exportToUri(id, uri)
                        } catch (_: Exception) {
                        }
                    }
                }
            }
        }
        finish()
    }

    private fun importFrom(data: Intent) {
        val uris = mutableListOf<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) {
                uris.add(clip.getItemAt(i).uri)
            }
        } else {
            data.data?.let { uris.add(it) }
        }
        for (uri in uris) {
            try {
                store.importUri(uri)
            } catch (_: Exception) {
                // Skip files that can't be read; the rest still import.
            }
        }
    }
}
