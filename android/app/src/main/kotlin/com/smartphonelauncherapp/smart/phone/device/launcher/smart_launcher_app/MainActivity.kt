package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app

import android.appwidget.AppWidgetHost
import android.content.Intent
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
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.WidgetsChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.widget.WidgetHostViewFactory

class MainActivity : FlutterActivity() {

    private val appWidgetHost by lazy { AppWidgetHost(this, 1024) }
    private var widgetsChannel: WidgetsChannel? = null
    private var notificationChannel: NotificationChannel? = null

    override fun getRenderMode(): RenderMode = RenderMode.texture
    override fun getTransparencyMode(): TransparencyMode = TransparencyMode.transparent

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
        appWidgetHost.startListening()
    }

    override fun onDestroy() {
        notificationChannel?.dispose()
        appWidgetHost.stopListening()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        AppsChannel(this).register(messenger)
        SystemChannel(this).register(messenger)
        WallpaperChannel(this).register(messenger)
        notificationChannel = NotificationChannel(this).also { it.register(messenger) }
        ContactsChannel(this).register(messenger)
        CalendarChannel(this).register(messenger)
        AlarmChannel(this).register(messenger)
        AppInstallEventChannel(this).register(messenger)
        widgetsChannel = WidgetsChannel(this, appWidgetHost).also { it.register(messenger) }

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.genrevibes.smartlauncher/widget_host_view",
            WidgetHostViewFactory(this, appWidgetHost),
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        notificationChannel?.dispose()
        notificationChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        widgetsChannel?.onActivityResult(requestCode, resultCode, data)
        super.onActivityResult(requestCode, resultCode, data)
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Launchers swallow the back button
    }
}
