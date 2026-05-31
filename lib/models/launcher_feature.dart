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
  final Color color;
  final String artworkId;

  const LauncherFeature({
    required this.id,
    required this.aliasClassName,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.artworkId,
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

class LauncherFeatureArtwork {
  final String id;
  final Color color;

  const LauncherFeatureArtwork({
    required this.id,
    required this.color,
  });
}

class LauncherFeatureCatalog {
  LauncherFeatureCatalog._();

  static const clockClass =
      'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.ClockActivity';
  static const fileLockerClass =
      'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.FileLockerActivity';
  static const appLockerClass =
      'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AppLockerActivity';
  static const appHiderClass =
      'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.AppHiderActivity';
  static const calculatorVaultClass =
      'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.CalculatorVaultActivity';
  static const notesVaultClass =
      'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.NotesVaultActivity';
  static const weatherVaultClass =
      'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.WeatherVaultActivity';
  static const browserVaultClass =
      'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.features.BrowserVaultActivity';

  static const fileLockerArtwork = LauncherFeatureArtwork(
    id: 'file_locker',
    color: Color(0xFF101014),
  );

  static const appHiderArtwork = LauncherFeatureArtwork(
    id: 'app_hider',
    color: Color(0xFF101014),
  );

  static const appLockerArtwork = LauncherFeatureArtwork(
    id: 'app_locker',
    color: Color(0xFF111114),
  );

  static const clockArtwork = LauncherFeatureArtwork(
    id: 'clock',
    color: Color(0xFF0B0B0D),
  );

  static const calculatorArtwork = LauncherFeatureArtwork(
    id: 'calculator',
    color: Color(0xFF171719),
  );

  static const notesArtwork = LauncherFeatureArtwork(
    id: 'notes',
    color: Color(0xFF312E81),
  );

  static const weatherArtwork = LauncherFeatureArtwork(
    id: 'weather',
    color: Color(0xFF075985),
  );

  static const browserArtwork = LauncherFeatureArtwork(
    id: 'browser',
    color: Color(0xFF172554),
  );

  static const fileLocker = LauncherFeature(
    id: 'file_locker',
    aliasClassName: fileLockerClass,
    title: 'File Locker',
    subtitle: 'Hide private files in an encrypted vault',
    color: Color(0xFF26A69A),
    artworkId: 'file_locker',
  );

  static const appHider = LauncherFeature(
    id: 'app_hider',
    aliasClassName: appHiderClass,
    title: 'App Hider',
    subtitle: 'Hide apps from drawer and search',
    color: Color(0xFF5C6BC0),
    artworkId: 'app_hider',
  );

  static const appLocker = LauncherFeature(
    id: 'app_locker',
    aliasClassName: appLockerClass,
    title: 'App Locker',
    subtitle: 'Require unlock for apps opened here',
    color: Color(0xFFEF5350),
    artworkId: 'app_locker',
  );

  static const alarmClock = LauncherFeature(
    id: 'alarm_clock',
    aliasClassName: clockClass,
    title: 'Clock',
    subtitle: 'Alarms, timers, and stopwatch shortcuts',
    color: Color(0xFFFFB300),
    artworkId: 'clock',
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

  static const Map<String, LauncherFeatureArtwork> byArtworkId = {
    'file_locker': fileLockerArtwork,
    'app_hider': appHiderArtwork,
    'app_locker': appLockerArtwork,
    'clock': clockArtwork,
    'calculator': calculatorArtwork,
    'notes': notesArtwork,
    'weather': weatherArtwork,
    'browser': browserArtwork,
  };

  static const Map<String, String> artworkIdByComponent = {
    '${LauncherFeature.launcherPackage}/$calculatorVaultClass': 'calculator',
    calculatorVaultClass: 'calculator',
    '${LauncherFeature.launcherPackage}/$notesVaultClass': 'notes',
    notesVaultClass: 'notes',
    '${LauncherFeature.launcherPackage}/$weatherVaultClass': 'weather',
    weatherVaultClass: 'weather',
    '${LauncherFeature.launcherPackage}/$browserVaultClass': 'browser',
    browserVaultClass: 'browser',
  };

  static final Map<String, LauncherFeature> byComponent = {
    for (final feature in homeFeatures) feature.componentName: feature,
    for (final feature in homeFeatures) feature.aliasClassName: feature,
    '${LauncherFeature.launcherPackage}/$calculatorVaultClass': appHider,
    calculatorVaultClass: appHider,
    '${LauncherFeature.launcherPackage}/$notesVaultClass': appHider,
    notesVaultClass: appHider,
    '${LauncherFeature.launcherPackage}/$weatherVaultClass': appHider,
    weatherVaultClass: appHider,
    '${LauncherFeature.launcherPackage}/$browserVaultClass': appHider,
    browserVaultClass: appHider,
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

  static LauncherFeatureArtwork? artworkForId(String? id) {
    final feature = fromId(id);
    if (feature == null) return null;
    return byArtworkId[feature.artworkId];
  }

  static LauncherFeatureArtwork? artworkForComponent(String? componentName) {
    if (componentName == null) return null;
    final artworkId = artworkIdByComponent[componentName] ??
        fromComponent(componentName)?.artworkId;
    return artworkId == null ? null : byArtworkId[artworkId];
  }

  static String? idForPackage(String packageName) => byPackage[packageName]?.id;

  static String? idForComponent(String? componentName) =>
      fromComponent(componentName)?.id;

  static String? idForApp(AppInfo app) =>
      app.launcherFeatureId ??
      idForComponent(app.appComponentName) ??
      idForPackage(app.packageName);
}
