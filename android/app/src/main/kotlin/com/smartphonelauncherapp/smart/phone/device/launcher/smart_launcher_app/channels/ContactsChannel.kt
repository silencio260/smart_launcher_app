package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.app.Activity
import android.provider.ContactsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class ContactsChannel(private val activity: Activity) {

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.genrevibes.smartlauncher/contacts")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "searchContacts" -> {
                        val query = call.argument<String>("query") ?: ""
                        try {
                            result.success(searchContacts(query))
                        } catch (e: Exception) {
                            result.success(emptyList<Map<String, Any?>>())
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun searchContacts(query: String): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val cursor = activity.contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
                ContactsContract.CommonDataKinds.Phone.PHOTO_URI,
            ),
            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?",
            arrayOf("%$query%"),
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC"
        ) ?: return results

        cursor.use {
            val nameCol = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
            val numberCol = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
            val photoCol = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.PHOTO_URI)
            while (it.moveToNext()) {
                results.add(mapOf(
                    "displayName" to it.getString(nameCol),
                    "phoneNumber" to it.getString(numberCol),
                    "photoUri" to it.getString(photoCol),
                ))
            }
        }
        return results
    }
}
