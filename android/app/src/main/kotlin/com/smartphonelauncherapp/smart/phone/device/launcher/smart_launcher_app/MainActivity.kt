package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app

import android.appwidget.AppWidgetHost
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.AlarmChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.AppInstallEventChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.AppsChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.CalendarChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.ContactsChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.NotificationChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.SystemChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.WallpaperChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.widget.WidgetHostViewFactory

class MainActivity : FlutterActivity() {

    private val appWidgetHost by lazy { AppWidgetHost(this, 1024) }

    override fun getRenderMode(): RenderMode = RenderMode.texture
    override fun getTransparencyMode(): TransparencyMode = TransparencyMode.transparent

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
        appWidgetHost.startListening()
    }

    override fun onDestroy() {
        appWidgetHost.stopListening()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        AppsChannel(this).register(messenger)
        SystemChannel(this).register(messenger)
        WallpaperChannel(this).register(messenger)
        NotificationChannel(this).register(messenger)
        ContactsChannel(this).register(messenger)
        CalendarChannel(this).register(messenger)
        AlarmChannel(this).register(messenger)
        AppInstallEventChannel(this).register(messenger)

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.genrevibes.smartlauncher/widget_host_view",
            WidgetHostViewFactory(this, appWidgetHost),
        )
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Launchers swallow the back button
    }
}
