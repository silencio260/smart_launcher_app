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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dragController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AppsCubit>().loadApps();
    }
  }

  void _openDrawer() {
    final settings = context.read<SettingsCubit>().state;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        pageBuilder: (routeCtx, _, __) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<AppsCubit>()),
            BlocProvider.value(value: context.read<SearchCubit>()),
            BlocProvider.value(value: context.read<SettingsCubit>()),
            BlocProvider.value(value: context.read<WorkspaceCubit>()),
          ],
          child: AllAppsContainer(
            settings: settings,
            onAppTap: (app) {
              Navigator.pop(routeCtx);
              LauncherService.launchApp(app.packageName);
            },
            onAppLongPress: (app) => _showDrawerAppMenu(app, routeCtx),
          ),
        ),
      ),
    );
  }

  void _showDrawerAppMenu(AppInfo app, BuildContext drawerCtx) {
    showModalBottomSheet(
      context: drawerCtx,
      backgroundColor: Colors.transparent,
      builder: (_) => _AppContextMenu(
        app: app,
        showAddToHome: true,
        onOpen: () {
          Navigator.pop(drawerCtx); // close menu
          Navigator.pop(drawerCtx); // close drawer
          LauncherService.launchApp(app.packageName);
        },
        onAddToHome: () {
          Navigator.pop(drawerCtx); // close menu
          Navigator.pop(drawerCtx); // close drawer
          _addAppToHomeScreen(app);
        },
        onAppInfo: () {
          Navigator.pop(drawerCtx);
          LauncherService.openAppSettings(app.packageName);
        },
        onHide: () {
          Navigator.pop(drawerCtx);
          context.read<AppsCubit>().hideApp(app.packageName);
        },
        onUninstall: () {
          Navigator.pop(drawerCtx);
          LauncherService.uninstallApp(app.packageName);
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

  void _showHomeMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _HomeContextMenu(
        onWallpaper: () {
          Navigator.pop(context);
          LauncherService.changeWallpaper();
        },
        onSettings: () {
          Navigator.pop(context);
          _openSettings();
        },
        onWidgets: () => Navigator.pop(context),
      ),
    );
  }

  void _showWorkspaceAppMenu(AppInfo app) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AppContextMenu(
        app: app,
        showAddToHome: false,
        onOpen: () {
          Navigator.pop(context);
          LauncherService.launchApp(app.packageName);
        },
        onAppInfo: () {
          Navigator.pop(context);
          LauncherService.openAppSettings(app.packageName);
        },
        onUninstall: () {
          Navigator.pop(context);
          LauncherService.uninstallApp(app.packageName);
        },
      ),
    );
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
                return DragLayer(
                  dragController: _dragController,
                  iconShape: settings.iconShape,
                  child: WorkspaceTouchListener(
                    settings: settings,
                    onDoubleTap: () => _handleGesture(settings.doubleTapAction),
                    onSwipeUp: () => _handleGesture(settings.swipeUpAction),
                    onSwipeDown: () => _handleGesture(settings.swipeDownAction),
                    onLongPress: _showHomeMenu,
                    child: Column(
                      children: [
                        SizedBox(height: MediaQuery.of(context).padding.top + 32),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SmartspaceView(settings: settings),
                        ),
                        Expanded(
                          child: WorkspaceView(
                            dragController: _dragController,
                            settings: settings,
                            badgeCounts: appsState.badgeCounts,
                            onAppTap: (app) => LauncherService.launchApp(app.packageName),
                            onAppLongPress: (app, page, slot) => _showWorkspaceAppMenu(app),
                            onPageChanged: (offset) {
                              const MethodChannel('com.genrevibes.smartlauncher/wallpaper')
                                  .invokeMethod('setWallpaperOffset', {'xOffset': offset});
                            },
                          ),
                        ),
                        if (settings.showDock)
                          Padding(
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
                              onAppTap: (app) => LauncherService.launchApp(app.packageName),
                              onAppLongPress: _showWorkspaceAppMenu,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  List<AppInfo> _resolveDockApps(AppsState appsState, LauncherSettings settings) {
    if (settings.dockPackages.isNotEmpty) {
      return settings.dockPackages
          .map((pkg) => appsState.apps.where((a) => a.packageName == pkg).firstOrNull)
          .whereType<AppInfo>()
          .toList();
    }
    const defaults = [
      'com.android.dialer',
      'com.android.contacts',
      'com.android.messaging',
      'com.android.chrome',
      'com.android.camera2',
    ];
    final pinned = appsState.apps.where((a) => defaults.contains(a.packageName)).toList();
    return pinned.isEmpty ? appsState.apps.take(settings.dockSize).toList() : pinned;
  }
}

// ─── Shared app context menu ──────────────────────────────────────────────────

class _AppContextMenu extends StatelessWidget {
  final AppInfo app;
  final bool showAddToHome;
  final VoidCallback onOpen;
  final VoidCallback? onAddToHome;
  final VoidCallback onAppInfo;
  final VoidCallback? onHide;
  final VoidCallback onUninstall;

  const _AppContextMenu({
    required this.app,
    required this.showAddToHome,
    required this.onOpen,
    this.onAddToHome,
    required this.onAppInfo,
    this.onHide,
    required this.onUninstall,
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
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              app.name,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new, color: Colors.white70),
            title: const Text('Open', style: TextStyle(color: Colors.white)),
            onTap: onOpen,
          ),
          if (showAddToHome && onAddToHome != null)
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
          if (onHide != null)
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined, color: Colors.white70),
              title: const Text('Hide App', style: TextStyle(color: Colors.white)),
              onTap: onHide,
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: const Text('Uninstall', style: TextStyle(color: Colors.redAccent)),
            onTap: onUninstall,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Home context menu ────────────────────────────────────────────────────────

class _HomeContextMenu extends StatelessWidget {
  final VoidCallback onWallpaper;
  final VoidCallback onSettings;
  final VoidCallback onWidgets;

  const _HomeContextMenu({
    required this.onWallpaper,
    required this.onSettings,
    required this.onWidgets,
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
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.wallpaper, color: Colors.white70),
            title: const Text('Change Wallpaper', style: TextStyle(color: Colors.white)),
            onTap: onWallpaper,
          ),
          ListTile(
            leading: const Icon(Icons.widgets_outlined, color: Colors.white70),
            title: const Text('Widgets', style: TextStyle(color: Colors.white)),
            onTap: onWidgets,
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined, color: Colors.white70),
            title: const Text('Launcher Settings', style: TextStyle(color: Colors.white)),
            onTap: onSettings,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
