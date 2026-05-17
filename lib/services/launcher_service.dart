import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/app_info.dart';
import '../models/widget_provider_info.dart';

class LauncherService {
  static const _apps = MethodChannel('com.genrevibes.smartlauncher/apps');
  static const _system = MethodChannel('com.genrevibes.smartlauncher/system');
  static const _widgets = MethodChannel('com.genrevibes.smartlauncher/widgets');

  static Future<List<AppInfo>> getInstalledApps() async {
    final List<dynamic> raw = await _apps.invokeMethod('getApps');
    final apps = raw.map((e) => AppInfo.fromMap(e as Map)).toList();
    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return apps;
  }

  static Future<bool> launchApp(String packageName) async {
    final result = await _apps
        .invokeMethod<bool>('launchApp', {'packageName': packageName});
    return result ?? false;
  }

  static Future<void> openAppSettings(String packageName) async {
    await _apps.invokeMethod('openAppSettings', {'packageName': packageName});
  }

  static Future<void> uninstallApp(String packageName) async {
    await _apps.invokeMethod('uninstallApp', {'packageName': packageName});
  }

  static Future<void> changeWallpaper() async {
    await _system.invokeMethod('changeWallpaper');
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
      debugPrint(
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
      debugPrint(
        '[LauncherServiceWidgets] getAvailableWidgets response count=${providers.length}',
      );
      for (final provider in providers) {
        debugPrint(
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
      debugPrint(
        '[LauncherServiceWidgets] getAvailableWidgets error=$error\n$stackTrace',
      );
      return [];
    }
  }

  /// Allocates and binds an app widget, returning its appWidgetId.
  /// Returns -1 if binding fails or the user cancels.
  static Future<int> bindWidget(
      String packageName, String providerClass) async {
    try {
      debugPrint(
        '[LauncherServiceWidgets] bindWidget request $packageName/$providerClass',
      );
      final int id = await _widgets.invokeMethod('bindWidget', {
        'packageName': packageName,
        'providerClass': providerClass,
      });
      debugPrint(
        '[LauncherServiceWidgets] bindWidget response id=$id provider=$packageName/$providerClass',
      );
      return id;
    } catch (error, stackTrace) {
      debugPrint('[LauncherServiceWidgets] bindWidget error=$error\n$stackTrace');
      return -1;
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
      debugPrint(
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
      debugPrint(
        '[LauncherServiceWidgets] updateWidgetSize complete id=$appWidgetId span=${spanX}x$spanY',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[LauncherServiceWidgets] updateWidgetSize error=$error\n$stackTrace',
      );
    }
  }
}
