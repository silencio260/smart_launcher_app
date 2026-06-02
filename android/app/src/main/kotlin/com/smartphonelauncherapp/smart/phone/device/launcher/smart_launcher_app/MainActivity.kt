package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app

import android.appwidget.AppWidgetHost
import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.AfterCallChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.AlarmChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.AppInstallEventChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.AppLockChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.AppsChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.CalendarChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.ContactsChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.InstallAssistantChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.overlay.AfterCallOverlay
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.FileLockerChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.NotificationChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.SecurityChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.SystemChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.WallpaperChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.channels.WidgetsChannel
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.widget.LauncherAppWidgetHost
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.widget.WidgetHostViewFactory
import com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.widget.WidgetHostViewRegistry

class MainActivity : FlutterActivity() {

    // DIAGNOSTIC: LauncherAppWidgetHost.onCreateView returns the instrumented
    // LauncherWidgetHostView so its onLayout/onMeasure JUMP logs actually fire.
    private val appWidgetHost by lazy { LauncherAppWidgetHost(this, 1024) }
    private var widgetsChannel: WidgetsChannel? = null
    private var notificationChannel: NotificationChannel? = null
    private var securityChannel: SecurityChannel? = null
    private var fileLockerChannel: FileLockerChannel? = null
    private var alarmChannel: AlarmChannel? = null

    override fun getRenderMode(): RenderMode = RenderMode.texture
    override fun getTransparencyMode(): TransparencyMode = TransparencyMode.transparent

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
        appWidgetHost.startListening()
        handleAfterCallIntent(intent)
        handleFeatureIntent(intent)
    }

    // singleTask: a tap on the after-call overlay re-enters this activity here.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAfterCallIntent(intent)
        handleFeatureIntent(intent)
    }

    private fun handleAfterCallIntent(intent: Intent?) {
        val action = intent?.getStringExtra(AfterCallOverlay.EXTRA_ACTION) ?: return
        intent.removeExtra(AfterCallOverlay.EXTRA_ACTION)
        AfterCallChannel.deliver(action)
    }

    private fun handleFeatureIntent(intent: Intent?) {
        val className = intent?.component?.className ?: return
        val featureId = when (className) {
            "$packageName.features.ClockActivity" -> "alarm_clock"
            "$packageName.features.FileLockerActivity" -> "file_locker"
            "$packageName.features.AppLockerActivity" -> "app_locker"
            "$packageName.features.AppHiderActivity" -> "app_hider"
            "$packageName.features.CalculatorVaultActivity" -> "app_hider"
            "$packageName.features.NotesVaultActivity" -> "app_hider"
            "$packageName.features.WeatherVaultActivity" -> "app_hider"
            "$packageName.features.BrowserVaultActivity" -> "app_hider"
            else -> null
        } ?: return
        SystemChannel.deliverFeatureRoute(featureId)
    }

    override fun onDestroy() {
        notificationChannel?.dispose()
        appWidgetHost.stopListening()
        // Pooled host views hold a reference to this activity context; drop
        // them so they don't leak across activity recreation.
        WidgetHostViewRegistry.clearPool()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        AppsChannel(this).register(messenger)
        SystemChannel(this).register(messenger)
        AppLockChannel(this).register(messenger)
        WallpaperChannel(this).register(messenger)
        notificationChannel = NotificationChannel(this).also { it.register(messenger) }
        ContactsChannel(this).register(messenger)
        CalendarChannel(this).register(messenger)
        AfterCallChannel(this).register(messenger)
        InstallAssistantChannel(this).register(messenger)
        alarmChannel = AlarmChannel(this).also { it.register(messenger) }
        securityChannel = SecurityChannel(this).also { it.register(messenger) }
        fileLockerChannel = FileLockerChannel(this).also { it.register(messenger) }
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
        if (securityChannel?.onActivityResult(requestCode, resultCode) == true) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        if (fileLockerChannel?.onActivityResult(requestCode, resultCode, data) == true) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        if (alarmChannel?.onActivityResult(requestCode, resultCode, data) == true) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        widgetsChannel?.onActivityResult(requestCode, resultCode, data)
        super.onActivityResult(requestCode, resultCode, data)
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Launchers swallow the back button
    }
}
