import 'package:flutter/material.dart';

import 'app_info.dart';
import 'item_info.dart';
import 'workspace_item_info.dart';

class LauncherFeature {
  static const launcherPackage =
      'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app';

  final String id;
  final String aliasClassName;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const LauncherFeature({
    required this.id,
    required this.aliasClassName,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  String get packageName => launcherPackage;

  String get componentName => '$launcherPackage/$aliasClassName';

  AppInfo toAppInfo() => AppInfo(
        id: componentName.hashCode,
        packageName: packageName,
        appComponentName: componentName,
        title: title,
        launcherFeatureId: id,
      );

  WorkspaceItemInfo toWorkspaceItem({int screenId = 0}) => WorkspaceItemInfo(
        id: componentName.hashCode,
        itemType: ItemType.application,
        packageName: packageName,
        componentName: componentName,
        title: title,
        launcherFeatureId: id,
        screenId: screenId,
      );
}

class LauncherFeatureCatalog {
  LauncherFeatureCatalog._();

  static const fileLocker = LauncherFeature(
    id: 'file_locker',
    aliasClassName:
        'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.FileLockerActivity',
    title: 'File Locker',
    subtitle: 'Hide private files in an encrypted vault',
    icon: Icons.enhanced_encryption_outlined,
    color: Color(0xFF26A69A),
  );

  static const appHider = LauncherFeature(
    id: 'app_hider',
    aliasClassName:
        'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AppHiderActivity',
    title: 'App Hider',
    subtitle: 'Hide apps from drawer and search',
    icon: Icons.visibility_off_outlined,
    color: Color(0xFF5C6BC0),
  );

  static const appLocker = LauncherFeature(
    id: 'app_locker',
    aliasClassName:
        'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AppLockerActivity',
    title: 'App Locker',
    subtitle: 'Require unlock for apps opened here',
    icon: Icons.lock_outline,
    color: Color(0xFFEF5350),
  );

  static const alarmClock = LauncherFeature(
    id: 'alarm_clock',
    aliasClassName:
        'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.ClockActivity',
    title: 'Alarm Clock',
    subtitle: 'Alarms, timers, and stopwatch shortcuts',
    icon: Icons.alarm_outlined,
    color: Color(0xFFFFB300),
  );

  static const homeFeatures = <LauncherFeature>[
    fileLocker,
    appHider,
    appLocker,
    alarmClock,
  ];

  static final Map<String, LauncherFeature> byId = {
    for (final feature in homeFeatures) feature.id: feature,
  };

  static final Map<String, LauncherFeature> byPackage = const {};

  static final Map<String, LauncherFeature> byComponent = {
    for (final feature in homeFeatures) feature.componentName: feature,
    for (final feature in homeFeatures) feature.aliasClassName: feature,
    '${LauncherFeature.launcherPackage}/com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.CalculatorVaultActivity':
        appHider,
    'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.CalculatorVaultActivity':
        appHider,
    '${LauncherFeature.launcherPackage}/com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.NotesVaultActivity':
        appHider,
    'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.NotesVaultActivity':
        appHider,
    '${LauncherFeature.launcherPackage}/com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.WeatherVaultActivity':
        appHider,
    'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.WeatherVaultActivity':
        appHider,
    '${LauncherFeature.launcherPackage}/com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.BrowserVaultActivity':
        appHider,
    'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.BrowserVaultActivity':
        appHider,
  };

  static List<AppInfo> get apps =>
      homeFeatures.map((feature) => feature.toAppInfo()).toList();

  static bool isFeaturePackage(String packageName) =>
      packageName == LauncherFeature.launcherPackage ||
      byPackage.containsKey(packageName);

  static bool isFeatureComponent(String componentName) =>
      byComponent.containsKey(componentName);

  static bool isFeatureApp(AppInfo app) =>
      app.launcherFeatureId != null ||
      byComponent.containsKey(app.appComponentName);

  static LauncherFeature? fromId(String? id) => id == null ? null : byId[id];

  static LauncherFeature? fromPackage(String packageName) =>
      byPackage[packageName];

  static LauncherFeature? fromComponent(String? componentName) =>
      componentName == null ? null : byComponent[componentName];

  static String? idForPackage(String packageName) => byPackage[packageName]?.id;

  static String? idForComponent(String? componentName) =>
      fromComponent(componentName)?.id;

  static String? idForApp(AppInfo app) =>
      app.launcherFeatureId ??
      idForComponent(app.appComponentName) ??
      idForPackage(app.packageName);
}
