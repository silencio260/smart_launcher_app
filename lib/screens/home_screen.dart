import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/app_info.dart';
import '../models/item_info.dart';
import '../models/launcher_settings.dart';
import '../models/launcher_state.dart' as ls;
import '../models/workspace_item_info.dart';
import '../services/launcher_service.dart';
import '../state/apps_cubit.dart';
import '../state/launcher_cubit.dart';
import '../state/search_cubit.dart';
import '../state/settings_cubit.dart';
import '../state/workspace_cubit.dart';
import '../widgets/allapps/all_apps_container.dart';
import '../widgets/dock/hotseat_view.dart';
import '../widgets/edit_mode/edit_mode_overlay.dart';
import '../widgets/drag/drag_layer.dart';
import '../widgets/smartspace/smartspace_view.dart';
import '../widgets/workspace/workspace_touch_listener.dart';
import '../widgets/workspace/workspace_view.dart';
import '../services/drag/drag_controller.dart';
import 'search_overlay_screen.dart';
import 'settings/settings_root_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _dragController = DragController();
  OverlayEntry? _appInfoTooltip;
  bool _drawerOpen = false;
  bool _editMode = false;
  PageController? _pageController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppsCubit>().startBadgeListening();
    });
    _dragController.addListener(_onDragChange);
  }

  void _onDragChange() {
    if (_dragController.isDragging) _dismissAppInfoTooltip();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dragController.removeListener(_onDragChange);
    _dragController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AppsCubit>().loadApps();
    }
  }

  void _openDrawer() => setState(() => _drawerOpen = true);

  void _closeDrawer() {
    setState(() => _drawerOpen = false);
    context.read<LauncherCubit>().goToState(ls.LauncherState.normal);
  }

  void _enterEditMode() {
    _dismissAppInfoTooltip();
    setState(() => _editMode = true);
  }

  void _exitEditMode() => setState(() => _editMode = false);

  void _showDrawerAppMenu(AppInfo app) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DrawerAppMenu(
        app: app,
        onAddToHome: () {
          Navigator.pop(context);
          _closeDrawer();
          _addAppToHomeScreen(app);
        },
        onAppInfo: () {
          Navigator.pop(context);
          LauncherService.openAppSettings(app.packageName);
        },
      ),
    );
  }

  void _addAppToHomeScreen(AppInfo app) {
    final workspaceState = context.read<WorkspaceCubit>().state;
    final settings = context.read<SettingsCubit>().state;
    final slotsPerPage = settings.gridColumns * settings.gridRows;

    int targetPage = -1;
    int targetSlot = -1;

    for (int p = 0; p < workspaceState.pages.length; p++) {
      for (int s = 0; s < slotsPerPage; s++) {
        if (workspaceState.pages[p].slots[s] == null) {
          targetPage = p;
          targetSlot = s;
          break;
        }
      }
      if (targetPage >= 0) break;
    }

    if (targetPage < 0) {
      context.read<WorkspaceCubit>().addPage();
      targetPage = workspaceState.pages.length;
      targetSlot = 0;
    }

    final item = WorkspaceItemInfo(
      id: app.id,
      itemType: ItemType.application,
      packageName: app.packageName,
      componentName: app.appComponentName,
      title: app.name,
      icon: app.icon,
      screenId: targetPage,
    );

    context.read<WorkspaceCubit>().addItem(item, targetPage, targetSlot);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${app.name} added to Home Screen'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.black87,
      ),
    );
  }

  void _handleGesture(GestureAction action) {
    switch (action) {
      case GestureAction.openDrawer:
        _openDrawer();
      case GestureAction.openSearch:
        _openSearch();
      case GestureAction.openNotifications:
        const MethodChannel('com.genrevibes.smartlauncher/system')
            .invokeMethod('expandNotifications');
      case GestureAction.openQuickSettings:
        const MethodChannel('com.genrevibes.smartlauncher/system')
            .invokeMethod('expandQuickSettings');
      case GestureAction.sleepScreen:
        const MethodChannel('com.genrevibes.smartlauncher/system')
            .invokeMethod('sleepScreen', {'method': 'accessibility'});
      case GestureAction.openRecents:
        const MethodChannel('com.genrevibes.smartlauncher/system')
            .invokeMethod('openRecents');
      case GestureAction.openAssistant:
        const MethodChannel('com.genrevibes.smartlauncher/system')
            .invokeMethod('openAssistant');
      case GestureAction.openCamera:
        LauncherService.launchApp('com.android.camera2');
      case GestureAction.openSettings:
        _openSettings();
      case GestureAction.none:
        break;
    }
  }

  void _openSearch() {
    final settings = context.read<SettingsCubit>().state;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<SearchCubit>()),
            BlocProvider.value(value: context.read<AppsCubit>()),
          ],
          child: SearchOverlayScreen(iconShape: settings.iconShape),
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<SettingsCubit>()),
            BlocProvider.value(value: context.read<AppsCubit>()),
            BlocProvider.value(value: context.read<WorkspaceCubit>()),
          ],
          child: const SettingsRootScreen(),
        ),
      ),
    );
  }

  void _showAppInfoTooltip(AppInfo app, Offset iconCenter) {
    _dismissAppInfoTooltip();
    final overlay = Overlay.of(context);
    _appInfoTooltip = OverlayEntry(
      builder: (_) => _AppInfoTooltip(
        app: app,
        iconCenter: iconCenter,
        onDismiss: _dismissAppInfoTooltip,
        onAppInfo: () {
          _dismissAppInfoTooltip();
          LauncherService.openAppSettings(app.packageName);
        },
      ),
    );
    overlay.insert(_appInfoTooltip!);
  }

  void _dismissAppInfoTooltip() {
    _appInfoTooltip?.remove();
    _appInfoTooltip = null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, LauncherSettings>(
      builder: (context, settings) {
        return BlocListener<LauncherCubit, ls.LauncherState>(
          listener: (context, state) {
            if (state == ls.LauncherState.allApps) _openDrawer();
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: BlocBuilder<AppsCubit, AppsState>(
              builder: (context, appsState) {
                final dockApps = _resolveDockApps(appsState, settings);
                return Stack(
                  children: [
                    DragLayer(
                      dragController: _dragController,
                      iconShape: settings.iconShape,
                      pageController: _pageController,
                      child: WorkspaceTouchListener(
                        settings: settings,
                        onDoubleTap: () => _handleGesture(settings.doubleTapAction),
                        onSwipeUp: () => _handleGesture(settings.swipeUpAction),
                        onSwipeDown: () => _handleGesture(settings.swipeDownAction),
                        onLongPress: _enterEditMode,
                        child: Column(
                          children: [
                            SizedBox(height: MediaQuery.of(context).padding.top + 32),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Visibility(
                                visible: !_drawerOpen,
                                maintainState: true,
                                child: SmartspaceView(settings: settings),
                              ),
                            ),
                            Expanded(
                              child: Visibility(
                                visible: !_drawerOpen,
                                maintainState: true,
                                maintainAnimation: true,
                                maintainSize: true,
                                child: WorkspaceView(
                                  dragController: _dragController,
                                  settings: settings,
                                  badgeCounts: appsState.badgeCounts,
                                  onAppTap: (app) => LauncherService.launchApp(app.packageName),
                                  onAppLongPress: (app, page, slot, center) =>
                                      _showAppInfoTooltip(app, center),
                                  onPageChanged: (offset) {
                                    const MethodChannel(
                                            'com.genrevibes.smartlauncher/wallpaper')
                                        .invokeMethod('setWallpaperOffset',
                                            {'xOffset': offset});
                                  },
                                  onControllerReady: (ctrl) =>
                                      setState(() => _pageController = ctrl),
                                ),
                              ),
                            ),
                            if (settings.showDock)
                              Visibility(
                                visible: !_drawerOpen,
                                maintainState: true,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    left: 12,
                                    right: 12,
                                    bottom: MediaQuery.of(context).padding.bottom + 12,
                                  ),
                                  child: HotseatView(
                                    apps: dockApps,
                                    settings: settings,
                                    badgeCounts: appsState.badgeCounts,
                                    dragController: _dragController,
                                    onSwipeUp: () => _handleGesture(settings.swipeUpAction),
                                    onAppTap: (app) =>
                                        LauncherService.launchApp(app.packageName),
                                    onAppLongPress: (app) =>
                                        _showAppInfoTooltip(app, Offset.zero),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (_drawerOpen)
                      AllAppsContainer(
                        settings: settings,
                        onDismiss: _closeDrawer,
                        onAppTap: (app) {
                          _closeDrawer();
                          LauncherService.launchApp(app.packageName);
                        },
                        onAppLongPress: _showDrawerAppMenu,
                      ),
                    if (_editMode)
                      EditModeOverlay(
                        settings: settings,
                        onDismiss: _exitEditMode,
                        onWallpaper: () {
                          _exitEditMode();
                          LauncherService.changeWallpaper();
                        },
                        onSettings: () {
                          _exitEditMode();
                          _openSettings();
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  List<AppInfo?> _resolveDockApps(AppsState appsState, LauncherSettings settings) {
    if (settings.dockPackages.isNotEmpty) {
      // Preserve slot positions: empty-string entries become null so the dock
      // displays an empty slot rather than shifting subsequent apps left.
      return settings.dockPackages.map((pkg) {
        if (pkg.isEmpty) return null;
        return appsState.apps.where((a) => a.packageName == pkg).firstOrNull;
      }).toList();
    }
    const defaults = [
      'com.android.dialer',
      'com.android.contacts',
      'com.android.messaging',
      'com.android.chrome',
      'com.android.camera2',
    ];
    final pinned = appsState.apps.where((a) => defaults.contains(a.packageName)).toList();
    final resolved = pinned.isEmpty ? appsState.apps.take(settings.dockSize).toList() : pinned;
    return resolved.map<AppInfo?>((a) => a).toList();
  }
}

// ─── Shared app context menu ──────────────────────────────────────────────────

class _DrawerAppMenu extends StatelessWidget {
  final AppInfo app;
  final VoidCallback onAddToHome;
  final VoidCallback onAppInfo;

  const _DrawerAppMenu({
    required this.app,
    required this.onAddToHome,
    required this.onAppInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900]!.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(app.name, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          ListTile(
            leading: const Icon(Icons.add_to_home_screen, color: Colors.white70),
            title: const Text('Add to Home Screen', style: TextStyle(color: Colors.white)),
            onTap: onAddToHome,
          ),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white70),
            title: const Text('App Info', style: TextStyle(color: Colors.white)),
            onTap: onAppInfo,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── App Info tooltip (non-blocking, dismisses on drag) ──────────────────────

class _AppInfoTooltip extends StatelessWidget {
  final AppInfo app;
  final Offset iconCenter;
  final VoidCallback onDismiss;
  final VoidCallback onAppInfo;

  const _AppInfoTooltip({
    required this.app,
    required this.iconCenter,
    required this.onDismiss,
    required this.onAppInfo,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const tooltipW = 160.0;
    const tooltipH = 48.0;

    // Position above the icon; clamp to screen bounds
    double left = (iconCenter.dx - tooltipW / 2).clamp(8.0, screenSize.width - tooltipW - 8);
    double top = (iconCenter.dy - tooltipH - 12).clamp(8.0, screenSize.height - tooltipH - 8);

    return Stack(
      children: [
        // Tap-outside dismisses
        Positioned.fill(child: GestureDetector(onTap: onDismiss, behavior: HitTestBehavior.translucent)),
        Positioned(
          left: left,
          top: top,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: tooltipW,
              height: tooltipH,
              decoration: BoxDecoration(
                color: Colors.grey[850]!.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3))],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onAppInfo,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.info_outline, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Text(app.name, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

