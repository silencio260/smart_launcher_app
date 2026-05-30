import 'package:flutter/material.dart';

import 'app_info.dart';
import 'item_info.dart';
import 'workspace_item_info.dart';

class LauncherFeature {
  final String id;
  final String packageName;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const LauncherFeature({
    required this.id,
    required this.packageName,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  AppInfo toAppInfo() => AppInfo(
        id: packageName.hashCode,
        packageName: packageName,
        appComponentName: packageName,
        title: title,
        launcherFeatureId: id,
      );

  WorkspaceItemInfo toWorkspaceItem({int screenId = 0}) => WorkspaceItemInfo(
        id: packageName.hashCode,
        itemType: ItemType.application,
        packageName: packageName,
        componentName: packageName,
        title: title,
        launcherFeatureId: id,
        screenId: screenId,
      );
}

class LauncherFeatureCatalog {
  LauncherFeatureCatalog._();

  static const fileLocker = LauncherFeature(
    id: 'file_locker',
    packageName: 'com.genrevibes.smartlauncher.features.file_locker',
    title: 'File Locker',
    subtitle: 'Hide private files in an encrypted vault',
    icon: Icons.enhanced_encryption_outlined,
    color: Color(0xFF26A69A),
  );

  static const appHider = LauncherFeature(
    id: 'app_hider',
    packageName: 'com.genrevibes.smartlauncher.features.app_hider',
    title: 'App Hider',
    subtitle: 'Hide apps from drawer and search',
    icon: Icons.visibility_off_outlined,
    color: Color(0xFF5C6BC0),
  );

  static const appLocker = LauncherFeature(
    id: 'app_locker',
    packageName: 'com.genrevibes.smartlauncher.features.app_locker',
    title: 'App Locker',
    subtitle: 'Require unlock for apps opened here',
    icon: Icons.lock_outline,
    color: Color(0xFFEF5350),
  );

  static const alarmClock = LauncherFeature(
    id: 'alarm_clock',
    packageName: 'com.genrevibes.smartlauncher.features.alarm_clock',
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

  static final Map<String, LauncherFeature> byPackage = {
    for (final feature in homeFeatures) feature.packageName: feature,
  };

  static List<AppInfo> get apps =>
      homeFeatures.map((feature) => feature.toAppInfo()).toList();

  static bool isFeaturePackage(String packageName) =>
      byPackage.containsKey(packageName);

  static LauncherFeature? fromId(String? id) => id == null ? null : byId[id];

  static LauncherFeature? fromPackage(String packageName) =>
      byPackage[packageName];

  static String? idForPackage(String packageName) => byPackage[packageName]?.id;
}
