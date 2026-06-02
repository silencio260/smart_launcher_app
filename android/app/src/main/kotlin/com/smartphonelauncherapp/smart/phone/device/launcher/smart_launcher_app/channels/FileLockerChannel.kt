package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.FileImportActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Method-channel surface for the vault. The actual file picking happens in
 * [FileImportActivity] (a non-`singleTask` activity) because the SAF picker's
 * result is dropped when launched from the `singleTask` MainActivity. All
 * storage/metadata work lives in [FileLockerStore].
 */
class FileLockerChannel(private val activity: Activity) {
    private val store = FileLockerStore(activity)

    // Thumbnail/view work touches disk; keep it off the UI thread. A small pool
    // (not a single thread) lets the grid's thumbnails load in parallel.
    private val io = Executors.newFixedThreadPool(4)
    private val main = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.genrevibes.smartlauncher/file_locker")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listFiles" -> result.success(store.listFiles())
                    "pickFiles" -> {
                        val delete = call.argument<Boolean>("deleteOriginals") ?: false
                        launchPicker(FileImportActivity.MODE_IMPORT, null, null, delete)
                        result.success(null)
                    }
                    "exportFile" -> {
                        val id = call.argument<String>("id")
                        if (id == null) {
                            result.success(false)
                        } else {
                            val name = store.findMeta(id)?.optString("name") ?: "locked-file"
                            launchPicker(FileImportActivity.MODE_EXPORT, id, name, false)
                            result.success(true)
                        }
                    }
                    "deleteFile" -> result.success(store.deleteFile(call.argument<String>("id")))
                    "thumbnail" -> {
                        val id = call.argument<String>("id")
                        if (id == null) result.success(null)
                        else runIo(result) { store.thumbnailBytes(id) }
                    }
                    "decryptToCache" -> {
                        val id = call.argument<String>("id")
                        if (id == null) result.success(null)
                        else runIo(result) { store.decryptToCacheFile(id) }
                    }
                    "clearViewCache" -> runIo(result) { store.clearViewCache(); null }
                    else -> result.notImplemented()
                }
            }
    }

    /** Runs [work] on the IO executor and delivers its value on the main thread. */
    private fun runIo(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            val value = try {
                work()
            } catch (_: Exception) {
                null
            }
            main.post { result.success(value) }
        }
    }

    /**
     * The picker runs in its own activity and reports nothing back through the
     * channel; Flutter reconciles imports via [store]'s file list on resume.
     * Kept so [com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.MainActivity]
     * can forward results without a compile break.
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean = false

    private fun launchPicker(mode: String, id: String?, name: String?, deleteOriginals: Boolean) {
        val intent = Intent(activity, FileImportActivity::class.java).apply {
            putExtra(FileImportActivity.EXTRA_MODE, mode)
            if (id != null) putExtra(FileImportActivity.EXTRA_ID, id)
            if (name != null) putExtra(FileImportActivity.EXTRA_NAME, name)
            putExtra(FileImportActivity.EXTRA_DELETE_ORIGINALS, deleteOriginals)
        }
        try {
            activity.startActivity(intent)
        } catch (_: Exception) {
        }
    }
}
