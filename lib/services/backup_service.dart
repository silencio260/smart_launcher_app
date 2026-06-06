import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/launcher_settings.dart';
import '../state/launcher_feature_cubit.dart';
import '../state/settings_cubit.dart';
import '../state/workspace_cubit.dart';

class BackupService {
  static const _version = 1;

  final SettingsCubit settingsCubit;
  final WorkspaceCubit workspaceCubit;
  final LauncherFeatureSettingsCubit? featureSettingsCubit;

  BackupService({
    required this.settingsCubit,
    required this.workspaceCubit,
    this.featureSettingsCubit,
  });

  Future<String?> export() async {
    try {
      final data = _buildPayload();
      final json = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await _getExportDir();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/smart_launcher_backup_$timestamp.json');
      await file.writeAsString(json);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<bool> importFromFile(String path) async {
    try {
      final json = await File(path).readAsString();
      final data = jsonDecode(json) as Map<String, dynamic>;
      return _applyPayload(data);
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _buildPayload() {
    final s = settingsCubit.state;
    final ws = workspaceCubit.state;
    return {
      'version': _version,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': _serializeSettings(s),
      if (featureSettingsCubit != null)
        'featureSettings': {
          'overlayMenusEnabled':
              featureSettingsCubit!.state.overlayMenusEnabled,
          'afterCallEnabled': featureSettingsCubit!.state.afterCallEnabled,
          'installUninstallAssistantEnabled':
              featureSettingsCubit!.state.installUninstallAssistantEnabled,
          'lockedApps': featureSettingsCubit!.state.lockedApps,
        },
      'workspace': _serializeWorkspace(ws),
    };
  }

  bool _applyPayload(Map<String, dynamic> data) {
    try {
      final version = data['version'] as int? ?? 0;
      if (version > _version) return false;

      final settingsData = data['settings'] as Map<String, dynamic>?;
      if (settingsData != null) {
        final restored = _deserializeSettings(settingsData);
        settingsCubit.update(restored);
      }
      final featureData = data['featureSettings'] as Map<String, dynamic>?;
      if (featureData != null && featureSettingsCubit != null) {
        featureSettingsCubit!.update(
          featureSettingsCubit!.state.copyWith(
            overlayMenusEnabled:
                featureData['overlayMenusEnabled'] as bool? ?? false,
            afterCallEnabled: featureData['afterCallEnabled'] as bool? ?? false,
            installUninstallAssistantEnabled:
                featureData['installUninstallAssistantEnabled'] as bool? ??
                    featureData['installAssistantEnabled'] as bool? ??
                    false,
            lockedApps: (featureData['lockedApps'] as List?)?.cast<String>() ??
                const [],
          ),
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _serializeSettings(LauncherSettings s) => {
        'themeMode': s.themeMode.index,
        'homeMode': s.homeMode.index,
        'settingsBackgroundMode': s.settingsBackgroundMode.index,
        'iconShape': s.iconShape,
        'iconPackPackage': s.iconPackPackage,
        'themedIconsEnabled': s.themedIconsEnabled,
        'notificationBadgesEnabled': s.notificationBadgesEnabled,
        'badgeShowCount': s.badgeShowCount,
        'gridColumns': s.gridColumns,
        'gridRows': s.gridRows,
        'lockHomeScreen': s.lockHomeScreen,
        'autoAddShortcuts': s.autoAddShortcuts,
        'infiniteScrolling': s.infiniteScrolling,
        'showGridDebugOverlay': s.showGridDebugOverlay,
        'showWidgetDragDebugLogs': s.showWidgetDragDebugLogs,
        'iconSize': s.iconSize,
        'showLabels': s.showLabels,
        'labelSize': s.labelSize,
        'showStatusBar': s.showStatusBar,
        'darkStatusBar': s.darkStatusBar,
        'textColorMode': s.textColorMode.index,
        'wallpaperScrolling': s.wallpaperScrolling,
        'wallpaperDepthEffect': s.wallpaperDepthEffect,
        'wallpaperBlur': s.wallpaperBlur,
        'wallpaperBlurIntensity': s.wallpaperBlurIntensity,
        'customWallpaperPath': s.customWallpaperPath,
        'iosGridColumns': s.iosGridColumns,
        'iosLibraryViewMode': s.iosLibraryViewMode.index,
        'iosDockPackages': s.iosDockPackages,
        'minimalFavoritePackages': s.minimalFavoritePackages,
        'minimalFontSize': s.minimalFontSize,
        'minimalUse24HourClock': s.minimalUse24HourClock,
        'minimalDayStartMinutes': s.minimalDayStartMinutes,
        'minimalDayEndMinutes': s.minimalDayEndMinutes,
        'showDock': s.showDock,
        'dockSize': s.dockSize,
        'dockShowBackground': s.dockShowBackground,
        'dockBackgroundOpacity': s.dockBackgroundOpacity,
        'showDockLabels': s.showDockLabels,
        'dockIconSize': s.dockIconSize,
        'dockPackages': s.dockPackages,
        'drawerLayout': s.drawerLayout.index,
        'drawerBackgroundOpacity': s.drawerBackgroundOpacity,
        'drawerColumns': s.drawerColumns,
        'drawerIconSize': s.drawerIconSize,
        'showDrawerLabels': s.showDrawerLabels,
        'drawerRememberScroll': s.drawerRememberScroll,
        'drawerShowScrollbar': s.drawerShowScrollbar,
        'hiddenApps': s.hiddenApps,
        'timeFormat': s.timeFormat.index,
        'workspaceFont': s.workspaceFont,
        'folderIconShape': s.folderIconShape,
        'folderMaxColumns': s.folderMaxColumns,
        'folderMaxRows': s.folderMaxRows,
        'showFolderLabels': s.showFolderLabels,
        'doubleTapAction': s.doubleTapAction.index,
        'swipeUpAction': s.swipeUpAction.index,
        'swipeDownAction': s.swipeDownAction.index,
        'twoFingerSwipeUpAction': s.twoFingerSwipeUpAction.index,
        'twoFingerSwipeDownAction': s.twoFingerSwipeDownAction.index,
        'homeBtnAction': s.homeBtnAction.index,
        'backBtnAction': s.backBtnAction.index,
      };

  LauncherSettings _deserializeSettings(Map<String, dynamic> d) {
    T enumAt<T>(List<T> values, String key, T fallback) {
      final idx = d[key] as int?;
      if (idx == null || idx < 0 || idx >= values.length) return fallback;
      return values[idx];
    }

    return LauncherSettings(
      themeMode: enumAt(ThemeMode2.values, 'themeMode', ThemeMode2.system),
      homeMode: enumAt(HomeMode.values, 'homeMode', HomeMode.smart),
      settingsBackgroundMode: enumAt(SettingsBackgroundMode.values,
          'settingsBackgroundMode', SettingsBackgroundMode.black),
      iconShape: d['iconShape'] as String? ?? 'squircle',
      iconPackPackage: d['iconPackPackage'] as String? ?? '',
      themedIconsEnabled: d['themedIconsEnabled'] as bool? ?? false,
      notificationBadgesEnabled:
          d['notificationBadgesEnabled'] as bool? ?? true,
      badgeShowCount: d['badgeShowCount'] as bool? ?? true,
      gridColumns: d['gridColumns'] as int? ?? 5,
      gridRows: d['gridRows'] as int? ?? 6,
      lockHomeScreen: d['lockHomeScreen'] as bool? ?? false,
      autoAddShortcuts: d['autoAddShortcuts'] as bool? ?? true,
      infiniteScrolling: d['infiniteScrolling'] as bool? ?? false,
      showGridDebugOverlay: d['showGridDebugOverlay'] as bool? ?? false,
      showWidgetDragDebugLogs: d['showWidgetDragDebugLogs'] as bool? ?? false,
      iconSize: (d['iconSize'] as num?)?.toDouble() ?? 56,
      showLabels: d['showLabels'] as bool? ?? true,
      labelSize: (d['labelSize'] as num?)?.toDouble() ?? 12,
      showStatusBar: d['showStatusBar'] as bool? ?? true,
      darkStatusBar: d['darkStatusBar'] as bool? ?? false,
      textColorMode:
          enumAt(TextColorMode.values, 'textColorMode', TextColorMode.auto),
      wallpaperScrolling: d['wallpaperScrolling'] as bool? ?? true,
      wallpaperDepthEffect: d['wallpaperDepthEffect'] as bool? ?? false,
      wallpaperBlur: d['wallpaperBlur'] as bool? ?? false,
      wallpaperBlurIntensity:
          (d['wallpaperBlurIntensity'] as num?)?.toDouble() ?? 0.3,
      customWallpaperPath: d['customWallpaperPath'] as String? ?? '',
      iosGridColumns: d['iosGridColumns'] as int? ?? 4,
      iosLibraryViewMode: enumAt(IosLibraryViewMode.values,
          'iosLibraryViewMode', IosLibraryViewMode.grid),
      iosDockPackages: (d['iosDockPackages'] as List?)?.cast<String>() ?? [],
      minimalFavoritePackages:
          (d['minimalFavoritePackages'] as List?)?.cast<String>() ?? [],
      minimalFontSize: (d['minimalFontSize'] as num?)?.toDouble() ?? 16,
      minimalUse24HourClock: d['minimalUse24HourClock'] as bool? ?? false,
      minimalDayStartMinutes: d['minimalDayStartMinutes'] as int? ?? 8 * 60,
      minimalDayEndMinutes: d['minimalDayEndMinutes'] as int? ?? 22 * 60,
      showDock: d['showDock'] as bool? ?? true,
      dockSize: d['dockSize'] as int? ?? 5,
      dockShowBackground: d['dockShowBackground'] as bool? ?? true,
      dockBackgroundOpacity:
          (d['dockBackgroundOpacity'] as num?)?.toDouble() ?? 0.4,
      showDockLabels: d['showDockLabels'] as bool? ?? false,
      dockIconSize: (d['dockIconSize'] as num?)?.toDouble() ?? 48,
      dockPackages: (d['dockPackages'] as List?)?.cast<String>() ?? [],
      drawerLayout:
          enumAt(DrawerLayout.values, 'drawerLayout', DrawerLayout.standard),
      drawerBackgroundOpacity:
          (d['drawerBackgroundOpacity'] as num?)?.toDouble() ?? 0.85,
      drawerColumns: d['drawerColumns'] as int? ?? 4,
      drawerIconSize: (d['drawerIconSize'] as num?)?.toDouble() ?? 56,
      showDrawerLabels: d['showDrawerLabels'] as bool? ?? true,
      drawerRememberScroll: d['drawerRememberScroll'] as bool? ?? false,
      drawerShowScrollbar: d['drawerShowScrollbar'] as bool? ?? true,
      hiddenApps: (d['hiddenApps'] as List?)?.cast<String>() ?? [],
      timeFormat: enumAt(TimeFormat.values, 'timeFormat', TimeFormat.h12),
      workspaceFont: d['workspaceFont'] as String? ?? '',
      folderIconShape: d['folderIconShape'] as String? ?? 'rounded_square',
      folderMaxColumns: d['folderMaxColumns'] as int? ?? 3,
      folderMaxRows: d['folderMaxRows'] as int? ?? 3,
      showFolderLabels: d['showFolderLabels'] as bool? ?? true,
      doubleTapAction: enumAt(
          GestureAction.values, 'doubleTapAction', GestureAction.sleepScreen),
      swipeUpAction: enumAt(
          GestureAction.values, 'swipeUpAction', GestureAction.openDrawer),
      swipeDownAction: enumAt(GestureAction.values, 'swipeDownAction',
          GestureAction.openNotifications),
      twoFingerSwipeUpAction: enumAt(
          GestureAction.values, 'twoFingerSwipeUpAction', GestureAction.none),
      twoFingerSwipeDownAction: enumAt(GestureAction.values,
          'twoFingerSwipeDownAction', GestureAction.openQuickSettings),
      homeBtnAction:
          enumAt(GestureAction.values, 'homeBtnAction', GestureAction.none),
      backBtnAction:
          enumAt(GestureAction.values, 'backBtnAction', GestureAction.none),
    );
  }

  Map<String, dynamic> _serializeWorkspace(WorkspaceState ws) => {
        'currentPage': ws.currentPage,
        'isLocked': ws.isLocked,
        'pageCount': ws.pages.length,
      };

  Future<Directory> _getExportDir() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir != null) return dir;
    } catch (_) {}
    return await getApplicationDocumentsDirectory();
  }
}
