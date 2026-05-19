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

    // RenderMode.surface uses a SurfaceView for Flutter output instead of a
    // TextureView. SurfaceView doesn't route frames through ImageReader, which
    // eliminates the "Unable to acquire a buffer item, very likely client tried
    // to acquire more than maxImages buffers" warning that fired whenever the
    // hosted AppWidgetHostView platform views (resize/scroll/edit-mode toggle)
    // produced frames faster than the ImageReader could drain. SurfaceView is
    // opaque — TransparencyMode must be opaque to match.
    override fun getRenderMode(): RenderMode = RenderMode.surface
    override fun getTransparencyMode(): TransparencyMode = TransparencyMode.opaque

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
        widgetsChannel = WidgetsChannel(this, appWidgetHost).also { it.register(messenger) }

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.genrevibes.smartlauncher/widget_host_view",
            WidgetHostViewFactory(this, appWidgetHost),
        )
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
