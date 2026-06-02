package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.content.Intent
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.FileImportActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Method-channel surface for the vault. The actual file picking happens in
 * [FileImportActivity] (a non-`singleTask` activity) because the SAF picker's
 * result is dropped when launched from the `singleTask` MainActivity. All
 * encryption/metadata work lives in [FileLockerStore].
 */
class FileLockerChannel(private val activity: Activity) {
    private val store = FileLockerStore(activity)

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.genrevibes.smartlauncher/file_locker")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listFiles" -> result.success(store.listFiles())
                    "pickFiles" -> {
                        launchPicker(FileImportActivity.MODE_IMPORT, null, null)
                        result.success(null)
                    }
                    "exportFile" -> {
                        val id = call.argument<String>("id")
                        if (id == null) {
                            result.success(false)
                        } else {
                            val name = store.findMeta(id)?.optString("name") ?: "locked-file"
                            launchPicker(FileImportActivity.MODE_EXPORT, id, name)
                            result.success(true)
                        }
                    }
                    "deleteFile" -> result.success(store.deleteFile(call.argument<String>("id")))
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * The picker runs in its own activity and reports nothing back through the
     * channel; Flutter reconciles imports via [store]'s file list on resume.
     * Kept so [com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.MainActivity]
     * can forward results without a compile break.
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean = false

    private fun launchPicker(mode: String, id: String?, name: String?) {
        val intent = Intent(activity, FileImportActivity::class.java).apply {
            putExtra(FileImportActivity.EXTRA_MODE, mode)
            if (id != null) putExtra(FileImportActivity.EXTRA_ID, id)
            if (name != null) putExtra(FileImportActivity.EXTRA_NAME, name)
        }
        try {
            activity.startActivity(intent)
        } catch (_: Exception) {
        }
    }
}
