package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class LocationChannel(private val activity: Activity) {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.genrevibes.smartlauncher/location")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceLocation" -> result.success(getDeviceLocation())
                    "requestLocationPermission" -> {
                        requestLocationPermission()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getDeviceLocation(): Map<String, Any?>? {
        if (!hasLocationPermission()) return null
        val manager = activity.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return null
        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER,
        )
        val best = providers.mapNotNull { provider ->
            try {
                if (manager.isProviderEnabled(provider)) manager.getLastKnownLocation(provider) else null
            } catch (_: SecurityException) {
                null
            } catch (_: Exception) {
                null
            }
        }.maxByOrNull { it.time } ?: return null
        return mapOf(
            "latitude" to best.latitude,
            "longitude" to best.longitude,
            "city" to cityName(best),
        )
    }

    private fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(
                activity,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED

    private fun requestLocationPermission() {
        if (hasLocationPermission()) return
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            9134,
        )
    }

    private fun cityName(location: Location): String? =
        try {
            @Suppress("DEPRECATION")
            val address = Geocoder(activity, Locale.getDefault())
                .getFromLocation(location.latitude, location.longitude, 1)
                ?.firstOrNull()
            address?.locality
                ?: address?.subAdminArea
                ?: address?.adminArea
        } catch (_: Exception) {
            null
        }
}
