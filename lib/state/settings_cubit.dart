import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/launcher_settings.dart';
import '../services/launcher_service.dart';
import '../utils/debug_flags.dart';
import '../utils/drawer_perf.dart';

class SettingsCubit extends Cubit<LauncherSettings> {
  static const _key = 'launcher_settings_v1';

  SettingsCubit() : super(const LauncherSettings());

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json != null) {
      try {
        emit(_fromJson(jsonDecode(json) as Map<String, dynamic>));
      } catch (_) {}
    }
    _applyDebugFlags(state);
  }

  Future<void> update(LauncherSettings settings) async {
    emit(settings);
    _applyDebugFlags(settings);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_toJson(settings)));
  }

  void _applyDebugFlags(LauncherSettings s) {
    DebugFlags.widgetLogs = s.showWidgetDebugLogs;
    DebugFlags.widgetPickerInfo = s.showWidgetPickerDebugInfo;
    DebugFlags.drawerPerfLogs = s.showDrawerPerfLogs;
    DebugFlags.routeCoverageLogs = s.showRouteCoverageLogs;
    DebugFlags.settingsLogs = s.showSettingsLogs;
    LauncherService.setWidgetDebugLogsEnabled(s.showWidgetDebugLogs);
    if (s.showDrawerPerfLogs) DrawerPerf.installGlobalTimings();
  }

  Future<void> reset() => update(const LauncherSettings());

  Map<String, dynamic> _toJson(LauncherSettings s) => {
        'themeMode': s.themeMode.index,
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
        'showWidgetDebugLogs': s.showWidgetDebugLogs,
        'showWidgetPickerDebugInfo': s.showWidgetPickerDebugInfo,
        'showDrawerPerfLogs': s.showDrawerPerfLogs,
        'showRouteCoverageLogs': s.showRouteCoverageLogs,
        'showSettingsLogs': s.showSettingsLogs,
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
        'showDock': s.showDock,
        'dockSize': s.dockSize,
        'dockShowBackground': s.dockShowBackground,
        'dockBackgroundColor': s.dockBackgroundColor.toARGB32(),
        'dockBackgroundOpacity': s.dockBackgroundOpacity,
        'showDockLabels': s.showDockLabels,
        'dockIconSize': s.dockIconSize,
        'dockPackages': s.dockPackages,
        'drawerLayout': s.drawerLayout.index,
        'drawerShowBackground': s.drawerShowBackground,
        'drawerBackgroundColor': s.drawerBackgroundColor.toARGB32(),
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
        'folderColor': s.folderColor.toARGB32(),
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

  LauncherSettings _fromJson(Map<String, dynamic> j) {
    T enumAt<T>(List<T> values, String key, T def) {
      final idx = j[key] as int?;
      return (idx != null && idx < values.length) ? values[idx] : def;
    }

    return LauncherSettings(
      themeMode: enumAt(ThemeMode2.values, 'themeMode', ThemeMode2.system),
      iconShape: j['iconShape'] as String? ?? 'squircle',
      iconPackPackage: j['iconPackPackage'] as String? ?? '',
      themedIconsEnabled: j['themedIconsEnabled'] as bool? ?? false,
      notificationBadgesEnabled:
          j['notificationBadgesEnabled'] as bool? ?? true,
      badgeShowCount: j['badgeShowCount'] as bool? ?? true,
      gridColumns: j['gridColumns'] as int? ?? 5,
      gridRows: j['gridRows'] as int? ?? 6,
      lockHomeScreen: j['lockHomeScreen'] as bool? ?? false,
      autoAddShortcuts: j['autoAddShortcuts'] as bool? ?? true,
      infiniteScrolling: j['infiniteScrolling'] as bool? ?? false,
      showGridDebugOverlay: j['showGridDebugOverlay'] as bool? ?? false,
      showWidgetDebugLogs: j['showWidgetDebugLogs'] as bool? ?? false,
      showWidgetPickerDebugInfo:
          j['showWidgetPickerDebugInfo'] as bool? ?? false,
      showDrawerPerfLogs: j['showDrawerPerfLogs'] as bool? ?? false,
      showRouteCoverageLogs: j['showRouteCoverageLogs'] as bool? ?? false,
      showSettingsLogs: j['showSettingsLogs'] as bool? ?? false,
      iconSize: (j['iconSize'] as num?)?.toDouble() ?? 56,
      showLabels: j['showLabels'] as bool? ?? true,
      labelSize: (j['labelSize'] as num?)?.toDouble() ?? 12,
      showStatusBar: j['showStatusBar'] as bool? ?? true,
      darkStatusBar: j['darkStatusBar'] as bool? ?? false,
      textColorMode:
          enumAt(TextColorMode.values, 'textColorMode', TextColorMode.auto),
      wallpaperScrolling: j['wallpaperScrolling'] as bool? ?? true,
      wallpaperDepthEffect: j['wallpaperDepthEffect'] as bool? ?? false,
      wallpaperBlur: j['wallpaperBlur'] as bool? ?? false,
      wallpaperBlurIntensity:
          (j['wallpaperBlurIntensity'] as num?)?.toDouble() ?? 0.3,
      showDock: j['showDock'] as bool? ?? true,
      dockSize: j['dockSize'] as int? ?? 5,
      dockShowBackground: j['dockShowBackground'] as bool? ?? true,
      dockBackgroundColor: j['dockBackgroundColor'] != null
          ? Color(j['dockBackgroundColor'] as int)
          : Colors.black,
      dockBackgroundOpacity:
          (j['dockBackgroundOpacity'] as num?)?.toDouble() ?? 0.4,
      showDockLabels: j['showDockLabels'] as bool? ?? false,
      dockIconSize: (j['dockIconSize'] as num?)?.toDouble() ?? 48,
      dockPackages: (j['dockPackages'] as List?)?.cast<String>() ?? [],
      drawerLayout:
          enumAt(DrawerLayout.values, 'drawerLayout', DrawerLayout.standard),
      drawerShowBackground: j['drawerShowBackground'] as bool? ?? false,
      drawerBackgroundColor: j['drawerBackgroundColor'] != null
          ? Color(j['drawerBackgroundColor'] as int)
          : Colors.black,
      drawerBackgroundOpacity:
          (j['drawerBackgroundOpacity'] as num?)?.toDouble() ?? 0.0,
      drawerColumns: j['drawerColumns'] as int? ?? 4,
      drawerIconSize: (j['drawerIconSize'] as num?)?.toDouble() ?? 56,
      showDrawerLabels: j['showDrawerLabels'] as bool? ?? true,
      drawerRememberScroll: j['drawerRememberScroll'] as bool? ?? false,
      drawerShowScrollbar: j['drawerShowScrollbar'] as bool? ?? true,
      hiddenApps: (j['hiddenApps'] as List?)?.cast<String>() ?? [],
      timeFormat: enumAt(TimeFormat.values, 'timeFormat', TimeFormat.h12),
      workspaceFont: j['workspaceFont'] as String? ?? '',
      folderIconShape: j['folderIconShape'] as String? ?? 'rounded_square',
      folderColor: j['folderColor'] != null
          ? Color(j['folderColor'] as int)
          : Colors.black54,
      folderMaxColumns: j['folderMaxColumns'] as int? ?? 3,
      folderMaxRows: j['folderMaxRows'] as int? ?? 3,
      showFolderLabels: j['showFolderLabels'] as bool? ?? true,
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
}
