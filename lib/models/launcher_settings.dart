import 'package:flutter/material.dart';
import 'package:equatable/equatable.dart';

enum ThemeMode2 { system, light, dark }

enum TextColorMode { auto, light, dark }

enum TimeFormat { h12, h24 }

enum DrawerLayout { standard, caddy }

enum GestureAction {
  none,
  openDrawer,
  openSearch,
  openNotifications,
  openQuickSettings,
  sleepScreen,
  openRecents,
  openAssistant,
  openCamera,
  openSettings,
}

class LauncherSettings extends Equatable {
  // General
  final ThemeMode2 themeMode;
  final String iconShape;
  final String iconPackPackage;
  final bool themedIconsEnabled;
  final bool notificationBadgesEnabled;
  final bool badgeShowCount;

  // Home screen grid
  final int gridColumns;
  final int gridRows;
  final bool lockHomeScreen;
  final bool autoAddShortcuts;
  final bool infiniteScrolling;
  final double iconSize;
  final bool showLabels;
  final double labelSize;
  final bool showStatusBar;
  final bool darkStatusBar;
  final TextColorMode textColorMode;
  final bool wallpaperScrolling;
  final bool wallpaperDepthEffect;
  final bool wallpaperBlur;
  final double wallpaperBlurIntensity;

  // Dock
  final bool showDock;
  final int dockSize;
  final bool dockShowBackground;
  final Color dockBackgroundColor;
  final double dockBackgroundOpacity;
  final bool showDockLabels;
  final double dockIconSize;
  final List<String> dockPackages;

  // Drawer
  final DrawerLayout drawerLayout;
  final bool drawerShowBackground;
  final Color drawerBackgroundColor;
  final double drawerBackgroundOpacity;
  final int drawerColumns;
  final double drawerIconSize;
  final bool showDrawerLabels;
  final bool drawerRememberScroll;
  final bool drawerShowScrollbar;
  final List<String> hiddenApps;

  // Smartspace
  final TimeFormat timeFormat;
  final String workspaceFont;

  // Folders
  final String folderIconShape;
  final Color folderColor;
  final int folderMaxColumns;
  final int folderMaxRows;
  final bool showFolderLabels;

  // Gestures
  final GestureAction doubleTapAction;
  final GestureAction swipeUpAction;
  final GestureAction swipeDownAction;
  final GestureAction twoFingerSwipeUpAction;
  final GestureAction twoFingerSwipeDownAction;
  final GestureAction homeBtnAction;
  final GestureAction backBtnAction;

  const LauncherSettings({
    this.themeMode = ThemeMode2.system,
    this.iconShape = 'squircle',
    this.iconPackPackage = '',
    this.themedIconsEnabled = false,
    this.notificationBadgesEnabled = true,
    this.badgeShowCount = true,
    this.gridColumns = 5,
    this.gridRows = 6,
    this.lockHomeScreen = false,
    this.autoAddShortcuts = true,
    this.infiniteScrolling = false,
    this.iconSize = 56,
    this.showLabels = true,
    this.labelSize = 12,
    this.showStatusBar = true,
    this.darkStatusBar = false,
    this.textColorMode = TextColorMode.auto,
    this.wallpaperScrolling = true,
    this.wallpaperDepthEffect = false,
    this.wallpaperBlur = false,
    this.wallpaperBlurIntensity = 0.3,
    this.showDock = true,
    this.dockSize = 5,
    this.dockShowBackground = false,
    this.dockBackgroundColor = Colors.white,
    this.dockBackgroundOpacity = 0.15,
    this.showDockLabels = false,
    this.dockIconSize = 48,
    this.dockPackages = const [],
    this.drawerLayout = DrawerLayout.standard,
    this.drawerShowBackground = false,
    this.drawerBackgroundColor = Colors.black,
    this.drawerBackgroundOpacity = 0.0,
    this.drawerColumns = 4,
    this.drawerIconSize = 56,
    this.showDrawerLabels = true,
    this.drawerRememberScroll = false,
    this.drawerShowScrollbar = true,
    this.hiddenApps = const [],
    this.timeFormat = TimeFormat.h12,
    this.workspaceFont = '',
    this.folderIconShape = 'rounded_square',
    this.folderColor = Colors.black54,
    this.folderMaxColumns = 3,
    this.folderMaxRows = 3,
    this.showFolderLabels = true,
    this.doubleTapAction = GestureAction.sleepScreen,
    this.swipeUpAction = GestureAction.openDrawer,
    this.swipeDownAction = GestureAction.openNotifications,
    this.twoFingerSwipeUpAction = GestureAction.none,
    this.twoFingerSwipeDownAction = GestureAction.openQuickSettings,
    this.homeBtnAction = GestureAction.none,
    this.backBtnAction = GestureAction.none,
  });

  LauncherSettings copyWith({
    ThemeMode2? themeMode,
    String? iconShape,
    String? iconPackPackage,
    bool? themedIconsEnabled,
    bool? notificationBadgesEnabled,
    bool? badgeShowCount,
    int? gridColumns,
    int? gridRows,
    bool? lockHomeScreen,
    bool? autoAddShortcuts,
    bool? infiniteScrolling,
    double? iconSize,
    bool? showLabels,
    double? labelSize,
    bool? showStatusBar,
    bool? darkStatusBar,
    TextColorMode? textColorMode,
    bool? wallpaperScrolling,
    bool? wallpaperDepthEffect,
    bool? wallpaperBlur,
    double? wallpaperBlurIntensity,
    bool? showDock,
    int? dockSize,
    bool? dockShowBackground,
    Color? dockBackgroundColor,
    double? dockBackgroundOpacity,
    bool? showDockLabels,
    double? dockIconSize,
    List<String>? dockPackages,
    DrawerLayout? drawerLayout,
    bool? drawerShowBackground,
    Color? drawerBackgroundColor,
    double? drawerBackgroundOpacity,
    int? drawerColumns,
    double? drawerIconSize,
    bool? showDrawerLabels,
    bool? drawerRememberScroll,
    bool? drawerShowScrollbar,
    List<String>? hiddenApps,
    TimeFormat? timeFormat,
    String? workspaceFont,
    String? folderIconShape,
    Color? folderColor,
    int? folderMaxColumns,
    int? folderMaxRows,
    bool? showFolderLabels,
    GestureAction? doubleTapAction,
    GestureAction? swipeUpAction,
    GestureAction? swipeDownAction,
    GestureAction? twoFingerSwipeUpAction,
    GestureAction? twoFingerSwipeDownAction,
    GestureAction? homeBtnAction,
    GestureAction? backBtnAction,
  }) {
    return LauncherSettings(
      themeMode: themeMode ?? this.themeMode,
      iconShape: iconShape ?? this.iconShape,
      iconPackPackage: iconPackPackage ?? this.iconPackPackage,
      themedIconsEnabled: themedIconsEnabled ?? this.themedIconsEnabled,
      notificationBadgesEnabled: notificationBadgesEnabled ?? this.notificationBadgesEnabled,
      badgeShowCount: badgeShowCount ?? this.badgeShowCount,
      gridColumns: gridColumns ?? this.gridColumns,
      gridRows: gridRows ?? this.gridRows,
      lockHomeScreen: lockHomeScreen ?? this.lockHomeScreen,
      autoAddShortcuts: autoAddShortcuts ?? this.autoAddShortcuts,
      infiniteScrolling: infiniteScrolling ?? this.infiniteScrolling,
      iconSize: iconSize ?? this.iconSize,
      showLabels: showLabels ?? this.showLabels,
      labelSize: labelSize ?? this.labelSize,
      showStatusBar: showStatusBar ?? this.showStatusBar,
      darkStatusBar: darkStatusBar ?? this.darkStatusBar,
      textColorMode: textColorMode ?? this.textColorMode,
      wallpaperScrolling: wallpaperScrolling ?? this.wallpaperScrolling,
      wallpaperDepthEffect: wallpaperDepthEffect ?? this.wallpaperDepthEffect,
      wallpaperBlur: wallpaperBlur ?? this.wallpaperBlur,
      wallpaperBlurIntensity: wallpaperBlurIntensity ?? this.wallpaperBlurIntensity,
      showDock: showDock ?? this.showDock,
      dockSize: dockSize ?? this.dockSize,
      dockShowBackground: dockShowBackground ?? this.dockShowBackground,
      dockBackgroundColor: dockBackgroundColor ?? this.dockBackgroundColor,
      dockBackgroundOpacity: dockBackgroundOpacity ?? this.dockBackgroundOpacity,
      showDockLabels: showDockLabels ?? this.showDockLabels,
      dockIconSize: dockIconSize ?? this.dockIconSize,
      dockPackages: dockPackages ?? this.dockPackages,
      drawerLayout: drawerLayout ?? this.drawerLayout,
      drawerShowBackground: drawerShowBackground ?? this.drawerShowBackground,
      drawerBackgroundColor: drawerBackgroundColor ?? this.drawerBackgroundColor,
      drawerBackgroundOpacity: drawerBackgroundOpacity ?? this.drawerBackgroundOpacity,
      drawerColumns: drawerColumns ?? this.drawerColumns,
      drawerIconSize: drawerIconSize ?? this.drawerIconSize,
      showDrawerLabels: showDrawerLabels ?? this.showDrawerLabels,
      drawerRememberScroll: drawerRememberScroll ?? this.drawerRememberScroll,
      drawerShowScrollbar: drawerShowScrollbar ?? this.drawerShowScrollbar,
      hiddenApps: hiddenApps ?? this.hiddenApps,
      timeFormat: timeFormat ?? this.timeFormat,
      workspaceFont: workspaceFont ?? this.workspaceFont,
      folderIconShape: folderIconShape ?? this.folderIconShape,
      folderColor: folderColor ?? this.folderColor,
      folderMaxColumns: folderMaxColumns ?? this.folderMaxColumns,
      folderMaxRows: folderMaxRows ?? this.folderMaxRows,
      showFolderLabels: showFolderLabels ?? this.showFolderLabels,
      doubleTapAction: doubleTapAction ?? this.doubleTapAction,
      swipeUpAction: swipeUpAction ?? this.swipeUpAction,
      swipeDownAction: swipeDownAction ?? this.swipeDownAction,
      twoFingerSwipeUpAction: twoFingerSwipeUpAction ?? this.twoFingerSwipeUpAction,
      twoFingerSwipeDownAction: twoFingerSwipeDownAction ?? this.twoFingerSwipeDownAction,
      homeBtnAction: homeBtnAction ?? this.homeBtnAction,
      backBtnAction: backBtnAction ?? this.backBtnAction,
    );
  }

  @override
  List<Object?> get props => [
        themeMode, iconShape, iconPackPackage, themedIconsEnabled,
        notificationBadgesEnabled, badgeShowCount, gridColumns, gridRows,
        lockHomeScreen, autoAddShortcuts, infiniteScrolling, iconSize,
        showLabels, labelSize, showStatusBar, darkStatusBar, textColorMode,
        wallpaperScrolling, wallpaperDepthEffect, wallpaperBlur, wallpaperBlurIntensity,
        showDock, dockSize, dockShowBackground, dockBackgroundColor, dockBackgroundOpacity,
        showDockLabels, dockIconSize, dockPackages, drawerLayout, drawerShowBackground,
        drawerBackgroundColor, drawerBackgroundOpacity, drawerColumns, drawerIconSize, showDrawerLabels,
        drawerRememberScroll, drawerShowScrollbar, hiddenApps, timeFormat, workspaceFont,
        folderIconShape, folderColor, folderMaxColumns, folderMaxRows, showFolderLabels,
        doubleTapAction, swipeUpAction, swipeDownAction, twoFingerSwipeUpAction,
        twoFingerSwipeDownAction, homeBtnAction, backBtnAction,
      ];
}
