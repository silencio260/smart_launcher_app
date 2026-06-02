import 'package:flutter/services.dart';
import '../models/app_info.dart';
import '../models/launcher_widget_info.dart';
import '../models/widget_provider_info.dart';
import '../utils/debug_flags.dart';

class AppListRefresh {
  final bool changed;
  final String? snapshotKey;
  final List<AppInfo>? apps;

  const AppListRefresh({
    required this.changed,
    required this.snapshotKey,
    required this.apps,
  });
}

class LauncherService {
  static const _apps = MethodChannel('com.genrevibes.smartlauncher/apps');
  static const _system = MethodChannel('com.genrevibes.smartlauncher/system');
  static const _widgets = MethodChannel('com.genrevibes.smartlauncher/widgets');
  static const _alarm = MethodChannel('com.genrevibes.smartlauncher/alarm');
  static const _security =
      MethodChannel('com.genrevibes.smartlauncher/security');
  static const _fileLocker =
      MethodChannel('com.genrevibes.smartlauncher/file_locker');
  static const _appLock =
      MethodChannel('com.genrevibes.smartlauncher/app_lock');

  static Future<List<AppInfo>> getInstalledApps() async {
    final List<dynamic> raw = await _apps.invokeMethod('getApps');
    return _sortedApps(raw);
  }

  static Future<AppListRefresh> refreshInstalledApps({
    String? knownSnapshotKey,
  }) async {
    final raw = await _apps.invokeMethod<Map<dynamic, dynamic>>(
      'getAppsIfChanged',
      {'snapshotKey': knownSnapshotKey},
    );
    if (raw == null) {
      final apps = await getInstalledApps();
      return AppListRefresh(
        changed: true,
        snapshotKey: null,
        apps: apps,
      );
    }
    final changed = raw['changed'] as bool? ?? true;
    final snapshotKey = raw['snapshotKey'] as String?;
    final appsRaw = raw['apps'] as List?;
    return AppListRefresh(
      changed: changed,
      snapshotKey: snapshotKey,
      apps: appsRaw == null ? null : _sortedApps(appsRaw),
    );
  }

  static List<AppInfo> _sortedApps(List<dynamic> raw) {
    final apps = raw.map((e) => AppInfo.fromMap(e as Map)).toList();
    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return apps;
  }

  static Future<bool> launchApp(String packageName) async {
    final result = await _apps
        .invokeMethod<bool>('launchApp', {'packageName': packageName});
    return result ?? false;
  }

  static Future<bool> launchComponent({
    required String packageName,
    required String componentName,
  }) async {
    final result = await _apps.invokeMethod<bool>('launchComponent', {
      'packageName': packageName,
      'componentName': componentName,
    });
    return result ?? false;
  }

  static Future<void> openAppSettings(String packageName) async {
    await _apps.invokeMethod('openAppSettings', {'packageName': packageName});
  }

  /// Whether this app is currently the system's default home launcher.
  static Future<bool> isDefaultLauncher() async {
    try {
      final result = await _system.invokeMethod<bool>('isDefaultLauncher');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Prompts the user to set this app as the default home launcher. Uses the
  /// RoleManager home-role dialog on Android 10+, otherwise opens Home settings.
  static Future<bool> requestHomeRole() async {
    try {
      final result = await _system.invokeMethod<bool>('requestHomeRole');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> uninstallApp(String packageName) async {
    await _apps.invokeMethod('uninstallApp', {'packageName': packageName});
  }

  static Future<bool> authenticateDevice({
    String title = 'Unlock',
    String description = 'Confirm your device lock to continue',
  }) async {
    final result = await _security.invokeMethod<bool>('authenticate', {
      'title': title,
      'description': description,
    });
    return result ?? false;
  }

  static Future<Map<String, dynamic>?> getNextAlarm() async {
    final raw =
        await _alarm.invokeMethod<Map<dynamic, dynamic>>('getNextAlarm');
    return raw?.cast<String, dynamic>();
  }

  static Future<bool> openAlarmApp() async =>
      await _alarm.invokeMethod<bool>('openAlarmApp') ?? false;

  static Future<bool> createAlarm() async =>
      await _alarm.invokeMethod<bool>('createAlarm') ?? false;

  /// Schedules a launcher-owned alarm/timer with the native AlarmManager.
  /// The full spec is mirrored natively so the ring service, repeat logic and
  /// reboot recovery work without the Dart engine running.
  static Future<bool> scheduleSmartAlarm({
    required String id,
    required int triggerAtMillis,
    required String label,
    int? hour,
    int? minute,
    List<int> repeatDays = const [],
    String? ringtoneUri,
    String ringtoneTitle = 'Default',
    bool vibrate = true,
    bool graduallyIncreaseVolume = false,
    int autoSilenceMinutes = 10,
    int snoozeMinutes = 5,
    String kind = 'alarm',
  }) async =>
      await _alarm.invokeMethod<bool>('scheduleSmartAlarm', {
        'id': id,
        'triggerAtMillis': triggerAtMillis,
        'label': label,
        'hour': hour,
        'minute': minute,
        'repeatDays': repeatDays,
        'ringtoneUri': ringtoneUri,
        'ringtoneTitle': ringtoneTitle,
        'vibrate': vibrate,
        'graduallyIncreaseVolume': graduallyIncreaseVolume,
        'autoSilenceMinutes': autoSilenceMinutes,
        'snoozeMinutes': snoozeMinutes,
        'kind': kind,
      }) ??
      false;

  static Future<bool> cancelSmartAlarm(String id) async =>
      await _alarm.invokeMethod<bool>('cancelSmartAlarm', {'id': id}) ?? false;

  /// Ids of one-shot alarms that fired while the app was closed, so the Dart
  /// model can switch them off. Clears the native list as a side effect.
  static Future<List<String>> consumeFiredAlarms() async {
    final raw = await _alarm.invokeMethod<List<dynamic>>('consumeFiredAlarms');
    return (raw ?? const []).map((e) => e.toString()).toList();
  }

  static Future<bool> canScheduleExactAlarms() async =>
      await _alarm.invokeMethod<bool>('canScheduleExactAlarms') ?? true;

  static Future<void> requestExactAlarmAccess() async {
    await _alarm.invokeMethod<void>('requestExactAlarmAccess');
  }

  /// Opens the system ringtone picker (alarm sounds). Returns the chosen
  /// `{uri, title}` or null if the user cancelled.
  static Future<Map<String, String>?> pickSystemRingtone({
    String? currentUri,
  }) async {
    final raw = await _alarm.invokeMethod<Map<dynamic, dynamic>>(
      'pickSystemRingtone',
      {'currentUri': currentUri},
    );
    if (raw == null) return null;
    return {
      'uri': raw['uri']?.toString() ?? '',
      'title': raw['title']?.toString() ?? 'Alarm sound',
    };
  }

  /// Opens the document picker for a custom audio file, persisting read access.
  /// Returns the chosen `{uri, title}` or null if cancelled.
  static Future<Map<String, String>?> pickCustomAudio() async {
    final raw = await _alarm
        .invokeMethod<Map<dynamic, dynamic>>('pickCustomAudio');
    if (raw == null) return null;
    return {
      'uri': raw['uri']?.toString() ?? '',
      'title': raw['title']?.toString() ?? 'Custom sound',
    };
  }

  /// Previews a tone (uri null = device default alarm) on the alarm stream.
  static Future<void> previewTone(String? uri) async {
    await _alarm.invokeMethod<void>('previewTone', {'uri': uri});
  }

  static Future<void> stopPreview() async {
    await _alarm.invokeMethod<void>('stopPreview');
  }

  /// Whether full-screen-intent alarms are permitted (always true < Android 14).
  static Future<bool> canUseFullScreenIntent() async =>
      await _alarm.invokeMethod<bool>('canUseFullScreenIntent') ?? true;

  static Future<void> requestFullScreenIntentAccess() async {
    await _alarm.invokeMethod<void>('requestFullScreenIntentAccess');
  }

  static Future<bool> isIgnoringBatteryOptimizations() async =>
      await _alarm.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? true;

  static Future<void> requestIgnoreBatteryOptimizations() async {
    await _alarm.invokeMethod<void>('requestIgnoreBatteryOptimizations');
  }

  static Future<bool> openTimer() async =>
      await _alarm.invokeMethod<bool>('openTimer') ?? false;

  static Future<bool> openStopwatch() async =>
      await _alarm.invokeMethod<bool>('openStopwatch') ?? false;

  static Future<bool> canDrawOverlays() async =>
      await _system.invokeMethod<bool>('canDrawOverlays') ?? false;

  static Future<bool> requestOverlayPermission() async =>
      await _system.invokeMethod<bool>('requestOverlayPermission') ?? false;

  static Future<bool> consumePendingFeatureRoute() async {
    final route =
        await _system.invokeMethod<String>('consumePendingFeatureRoute');
    return route != null && route.isNotEmpty;
  }

  static Future<String?> consumePendingFeatureId() async {
    return _system.invokeMethod<String>('consumePendingFeatureRoute');
  }

  static Future<void> setDeviceLockedApps(List<String> packageNames) async {
    await _system.invokeMethod<void>('setDeviceLockedApps', {
      'packageNames': packageNames,
    });
  }

  /// Mirrors the App Lock credential to native so the device-wide lock overlay
  /// (which runs with no Flutter engine) can verify it. [hash] must be the
  /// exact `sha256("$salt::$code")` the Dart `AppLockSecurityRepository`
  /// computes, so the native side recomputes and compares identically.
  static Future<void> setAppLockCredential({
    required String type,
    required String salt,
    required String hash,
  }) async {
    try {
      await _appLock.invokeMethod<void>('setAppLockCredential', {
        'type': type,
        'salt': salt,
        'hash': hash,
      });
    } catch (_) {
      // Channel may not be ready during cold start; the repo re-mirrors on the
      // next credential write.
    }
  }

  static Future<void> setAppLockBiometricEnabled(bool enabled) async {
    try {
      await _appLock.invokeMethod<void>('setAppLockBiometricEnabled', {
        'enabled': enabled,
      });
    } catch (_) {}
  }

  static Future<void> clearAppLockCredential() async {
    try {
      await _appLock.invokeMethod<void>('clearAppLockCredential');
    } catch (_) {}
  }

  static Future<bool> isUsageAccessEnabled() async =>
      await _system.invokeMethod<bool>('isUsageAccessEnabled') ?? false;

  static Future<void> requestUsageAccess() async {
    await _system.invokeMethod<void>('requestUsageAccess');
  }

  static Future<bool> isAccessibilityServiceEnabled() async =>
      await _system.invokeMethod<bool>('isAccessibilityServiceEnabled') ??
      false;

  static Future<void> requestAccessibilityAccess() async {
    await _system.invokeMethod<void>('requestAccessibilityAccess');
  }

  static Future<void> setAppHiderDisguise(String label) async {
    await _system.invokeMethod<void>('setAppHiderDisguise', {'label': label});
  }

  static Future<List<Map<String, dynamic>>> listLockedFiles() async {
    final raw = await _fileLocker.invokeMethod<List<dynamic>>('listFiles');
    return (raw ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);
  }

  /// Opens the multi-select system file picker in a standalone activity and
  /// encrypts the chosen files into the vault. The picker runs in its own task
  /// (the launcher is `singleTask`, which drops `onActivityResult`), so this
  /// returns immediately after launching; the caller reconciles the imported
  /// files via [listLockedFiles] once it regains focus.
  ///
  /// When [deleteOriginals] is true the source files are removed from the
  /// gallery after a successful import (a true "hide"). On Android 11+ the
  /// system shows a one-time delete-confirmation dialog.
  static Future<void> pickVaultFiles({bool deleteOriginals = false}) async {
    await _fileLocker.invokeMethod<void>(
      'pickFiles',
      {'deleteOriginals': deleteOriginals},
    );
  }

  static Future<bool> exportLockedFile(String id) async =>
      await _fileLocker.invokeMethod<bool>('exportFile', {'id': id}) ?? false;

  static Future<bool> deleteLockedFile(String id) async =>
      await _fileLocker.invokeMethod<bool>('deleteFile', {'id': id}) ?? false;

  /// The decrypted JPEG preview for a vault item, or null when there is none
  /// (documents and files we couldn't decode have no thumbnail).
  static Future<Uint8List?> vaultThumbnail(String id) async =>
      _fileLocker.invokeMethod<Uint8List>('thumbnail', {'id': id});

  /// Decrypts a vault item into a private cache file and returns its path, so
  /// the in-app viewer can display/play it. The cache is wiped on lock via
  /// [clearVaultViewCache].
  static Future<String?> vaultDecryptToCache(String id) async =>
      _fileLocker.invokeMethod<String>('decryptToCache', {'id': id});

  /// Removes every decrypted preview file. Called whenever the vault re-locks.
  static Future<void> clearVaultViewCache() async {
    await _fileLocker.invokeMethod<void>('clearViewCache');
  }

  static Future<void> changeWallpaper() async {
    await _system.invokeMethod('changeWallpaper');
  }

  /// Toggles widget-related Log.d/w output on the native side.
  static Future<void> setWidgetDebugLogsEnabled(bool enabled) async {
    try {
      await _widgets.invokeMethod('setWidgetDebugLogs', {'enabled': enabled});
    } catch (_) {
      // Channel may not be ready on the very first call during cold start;
      // SettingsCubit will re-apply on the next settings change.
    }
  }

  /// Toggles detailed widget drag/drop diagnostics on the native side.
  static Future<void> setWidgetDragDebugLogsEnabled(bool enabled) async {
    try {
      await _widgets.invokeMethod(
        'setWidgetDragDebugLogs',
        {'enabled': enabled},
      );
    } catch (_) {
      // Channel may not be ready during cold start; SettingsCubit reapplies.
    }
  }

  /// Returns a list of all app widget providers installed on the device.
  static Future<List<WidgetProviderInfo>> getAvailableWidgets({
    int? gridColumns,
    int? gridRows,
    double? cellWidth,
    double? cellHeight,
    double? gap,
  }) async {
    try {
      widgetLog(
        '[LauncherServiceWidgets] getAvailableWidgets request '
        'grid=${gridColumns}x$gridRows cell=${cellWidth?.toStringAsFixed(2)}x${cellHeight?.toStringAsFixed(2)} gap=$gap',
      );
      final List<dynamic> raw = await _widgets.invokeMethod(
        'getAvailableWidgets',
        {
          if (gridColumns != null) 'gridColumns': gridColumns,
          if (gridRows != null) 'gridRows': gridRows,
          if (cellWidth != null) 'cellWidth': cellWidth,
          if (cellHeight != null) 'cellHeight': cellHeight,
          if (gap != null) 'gap': gap,
        },
      );
      final providers =
          raw.map((e) => WidgetProviderInfo.fromMap(e as Map)).toList();
      widgetLog(
        '[LauncherServiceWidgets] getAvailableWidgets response count=${providers.length}',
      );
      for (final provider in providers) {
        if (!DebugFlags.widgetLogs) break;
        widgetLog(
          '[LauncherServiceWidgets] provider '
          '${provider.packageName}/${provider.providerClass} '
          'label="${provider.label}" '
          'rawMin=${provider.minWidth}x${provider.minHeight} '
          'rawMinResize=${provider.minResizeWidth}x${provider.minResizeHeight} '
          'rawMaxResize=${provider.maxResizeWidth}x${provider.maxResizeHeight} '
          'target=${provider.targetCellWidth}x${provider.targetCellHeight} '
          'resizeMode=${provider.resizeMode} '
          'span=${provider.spanX}x${provider.spanY} '
          'minSpan=${provider.minSpanX}x${provider.minSpanY} '
          'maxSpan=${provider.maxSpanX}x${provider.maxSpanY}',
        );
      }
      return providers;
    } catch (error, stackTrace) {
      widgetLog(
        '[LauncherServiceWidgets] getAvailableWidgets error=$error\n$stackTrace',
      );
      return [];
    }
  }

  /// Returns provider sizing metadata only for widgets already placed on home.
  static Future<List<WidgetProviderInfo>> getPlacedWidgetProviderMetadata({
    required List<LauncherWidgetInfo> widgets,
    int? gridColumns,
    int? gridRows,
    double? cellWidth,
    double? cellHeight,
    double? gap,
  }) async {
    if (widgets.isEmpty) return [];
    try {
      final stopwatch = Stopwatch()..start();
      widgetLog(
        '[LauncherServiceWidgets] getPlacedWidgetProviderMetadata request '
        'count=${widgets.length} grid=${gridColumns}x$gridRows '
        'cell=${cellWidth?.toStringAsFixed(2)}x${cellHeight?.toStringAsFixed(2)} gap=$gap',
      );
      final List<dynamic> raw = await _widgets.invokeMethod(
        'getPlacedWidgetProviderMetadata',
        {
          'widgets': widgets
              .map((widget) => {
                    'appWidgetId': widget.appWidgetId,
                    'providerPackage': widget.providerPackage,
                    'providerClass': widget.providerClass,
                  })
              .toList(growable: false),
          if (gridColumns != null) 'gridColumns': gridColumns,
          if (gridRows != null) 'gridRows': gridRows,
          if (cellWidth != null) 'cellWidth': cellWidth,
          if (cellHeight != null) 'cellHeight': cellHeight,
          if (gap != null) 'gap': gap,
        },
      );
      final providers =
          raw.map((e) => WidgetProviderInfo.fromMap(e as Map)).toList();
      widgetLog(
        '[LauncherServiceWidgets] getPlacedWidgetProviderMetadata response '
        'count=${providers.length} durationMs=${stopwatch.elapsedMilliseconds}',
      );
      return providers;
    } catch (error, stackTrace) {
      widgetLog(
        '[LauncherServiceWidgets] getPlacedWidgetProviderMetadata error=$error\n$stackTrace',
      );
      return [];
    }
  }

  /// Allocates and binds an app widget, returning its appWidgetId.
  /// Returns -1 if binding fails or the user cancels.
  static Future<int> bindWidget(
      String packageName, String providerClass) async {
    try {
      widgetLog(
        '[LauncherServiceWidgets] bindWidget request $packageName/$providerClass',
      );
      final int id = await _widgets.invokeMethod('bindWidget', {
        'packageName': packageName,
        'providerClass': providerClass,
      });
      widgetLog(
        '[LauncherServiceWidgets] bindWidget response id=$id provider=$packageName/$providerClass',
      );
      return id;
    } catch (error, stackTrace) {
      widgetLog(
        '[LauncherServiceWidgets] bindWidget error=$error\n$stackTrace',
      );
      return -1;
    }
  }

  /// Returns a PNG snapshot of the currently-rendered AppWidgetHostView for
  /// [appWidgetId]. Returns null if no live host view is registered for that
  /// id (e.g. the workspace hasn't laid it out yet), so callers should fall
  /// back to the static provider preview image.
  static Future<Uint8List?> renderLiveWidget(
    int appWidgetId, {
    int maxWidthPx = 360,
    int maxHeightPx = 360,
  }) async {
    if (appWidgetId <= 0) return null;
    try {
      final result = await _widgets.invokeMethod<Uint8List>(
        'renderLiveWidget',
        {
          'appWidgetId': appWidgetId,
          'maxWidthPx': maxWidthPx,
          'maxHeightPx': maxHeightPx,
        },
      );
      return result;
    } catch (error, stackTrace) {
      widgetLog(
        '[LauncherServiceWidgets] renderLiveWidget error=$error\n$stackTrace',
      );
      return null;
    }
  }

  static Future<void> updateWidgetSize(
    int appWidgetId,
    String providerPackage,
    String providerClass,
    int spanX,
    int spanY, {
    int? gridColumns,
    int? gridRows,
    double? cellWidth,
    double? cellHeight,
    double? gap,
  }) async {
    try {
      widgetLog(
        '[LauncherServiceWidgets] updateWidgetSize request '
        'id=$appWidgetId provider=$providerPackage/$providerClass '
        'span=${spanX}x$spanY grid=${gridColumns}x$gridRows '
        'cell=${cellWidth?.toStringAsFixed(2)}x${cellHeight?.toStringAsFixed(2)} gap=$gap',
      );
      await _widgets.invokeMethod('updateWidgetSize', {
        'appWidgetId': appWidgetId,
        'providerPackage': providerPackage,
        'providerClass': providerClass,
        'spanX': spanX,
        'spanY': spanY,
        if (gridColumns != null) 'gridColumns': gridColumns,
        if (gridRows != null) 'gridRows': gridRows,
        if (cellWidth != null) 'cellWidth': cellWidth,
        if (cellHeight != null) 'cellHeight': cellHeight,
        if (gap != null) 'gap': gap,
      });
      widgetLog(
        '[LauncherServiceWidgets] updateWidgetSize complete id=$appWidgetId span=${spanX}x$spanY',
      );
    } catch (error, stackTrace) {
      widgetLog(
        '[LauncherServiceWidgets] updateWidgetSize error=$error\n$stackTrace',
      );
    }
  }
}
