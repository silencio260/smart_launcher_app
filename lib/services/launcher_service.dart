import 'package:flutter/services.dart';
import '../models/app_info.dart';

class LauncherService {
  static const _apps = MethodChannel('com.genrevibes.smartlauncher/apps');
  static const _system = MethodChannel('com.genrevibes.smartlauncher/system');

  static Future<List<AppInfo>> getInstalledApps() async {
    final List<dynamic> raw = await _apps.invokeMethod('getApps');
    final apps = raw
        .map((e) => AppInfo.fromMap(e as Map))
        .toList();
    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return apps;
  }

  static Future<bool> launchApp(String packageName) async {
    final result = await _apps.invokeMethod<bool>('launchApp', {'packageName': packageName});
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
}
