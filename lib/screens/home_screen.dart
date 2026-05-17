import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/app_info.dart';
import '../models/folder_info.dart';
import '../models/item_info.dart';
import '../models/launcher_widget_info.dart';
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
import '../widgets/edit_mode/edit_mode_scope.dart';
import '../widgets/drag/drag_layer.dart';
import '../widgets/workspace/workspace_touch_listener.dart';
import '../widgets/workspace/workspace_view.dart';
import '../services/drag/drag_controller.dart';
import 'search_overlay_screen.dart';
import 'settings/general_settings_screen.dart';
import 'settings/settings_root_screen.dart';
import 'settings/widget_picker_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _dragController = DragController();
  OverlayEntry? _appInfoTooltip;
  bool _drawerOpen = false;
  bool _drawerDraggingToHome = false;
  bool _editMode = false;
  bool _didEnsureDefaultClock = false;
  bool _normalizingDock = false;
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
    _dragController.onRevertDisplacements = (displacements) {
      final workspace = context.read<WorkspaceCubit>();
      for (final d in displacements) {
        workspace.moveItem(d.page, d.toSlot, d.page, d.fromSlot);
      }
    };
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
    setState(() {
      _drawerOpen = false;
      _drawerDraggingToHome = false;
    });
    context.read<LauncherCubit>().goToState(ls.LauncherState.normal);
  }

  void _enterEditMode() {
    _dismissAppInfoTooltip();
    setState(() => _editMode = true);
  }

  void _exitEditMode() => setState(() => _editMode = false);

  void _navigateToBestDragPage() {
    final workspace = context.read<WorkspaceCubit>();
    final settings = context.read<SettingsCubit>().state;
    final placement = workspace.ensureAppPlacement(
      settings.gridColumns,
      settings.gridRows,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageController?.animateToPage(
        placement.page,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  void _addAppToHomeScreen(AppInfo app) {
    final workspace = context.read<WorkspaceCubit>();
    final settings = context.read<SettingsCubit>().state;
    final placement = workspace.addAppToFirstAvailableSlot(
      WorkspaceItemInfo(
        id: app.id,
        itemType: ItemType.application,
        packageName: app.packageName,
        componentName: app.appComponentName,
        title: app.name,
        icon: app.icon,
        screenId: 0,
      ),
      settings.gridColumns,
      settings.gridRows,
    );

    // Navigate to the page where the app was placed.
    final page = placement.page;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageController?.animateToPage(
        page,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${app.name} added to Home Screen'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.black87,
      ),
    );
  }

  void _addWidgetToHomeScreen(LauncherWidgetInfo widget, int page) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageController?.animateToPage(
        page,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  void _ensureDefaultClockWidget(
    WorkspaceState workspaceState,
    LauncherSettings settings,
  ) {
    if (_didEnsureDefaultClock || workspaceState.pages.isEmpty) return;
    _didEnsureDefaultClock = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<WorkspaceCubit>().ensureDefaultClockWidget(
            settings.gridColumns,
            settings.gridRows,
          );
    });
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
          child: SettingsRootScreen(onWidgetAdded: _addWidgetToHomeScreen),
        ),
      ),
    );
  }

  void _openThemes() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<SettingsCubit>()),
            BlocProvider.value(value: context.read<AppsCubit>()),
          ],
          child: const GeneralSettingsScreen(),
        ),
      ),
    );
  }

  void _openWidgetPicker() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<SettingsCubit>()),
            BlocProvider.value(value: context.read<AppsCubit>()),
            BlocProvider.value(value: context.read<WorkspaceCubit>()),
          ],
          child: WidgetPickerScreen(onWidgetAdded: _addWidgetToHomeScreen),
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
    return MultiBlocListener(
      listeners: [
        BlocListener<LauncherCubit, ls.LauncherState>(
          listener: (context, state) {
            if (state == ls.LauncherState.allApps) _openDrawer();
          },
        ),
        // One-shot default clock seed. Listen instead of watch so the entire
        // HomeScreen subtree (workspace, dock, every AndroidView) doesn't
        // rebuild on every WorkspaceCubit emit.
        BlocListener<WorkspaceCubit, WorkspaceState>(
          listenWhen: (_, curr) =>
              !_didEnsureDefaultClock && curr.pages.isNotEmpty,
          listener: (context, state) {
            _ensureDefaultClockWidget(
              state,
              context.read<SettingsCubit>().state,
            );
          },
        ),
        BlocListener<SettingsCubit, LauncherSettings>(
          listenWhen: (prev, next) =>
              prev.gridColumns != next.gridColumns ||
              prev.gridRows != next.gridRows ||
              prev.dockSize != next.dockSize,
          listener: (context, settings) {
            context
                .read<WorkspaceCubit>()
                .normalizeLayout(settings.gridColumns, settings.gridRows);
            _normalizeDockForCurrentState();
          },
        ),
        BlocListener<AppsCubit, AppsState>(
          listenWhen: (prev, next) => prev.apps != next.apps,
          listener: (_, __) => _normalizeDockForCurrentState(),
        ),
      ],
      child: BlocBuilder<SettingsCubit, LauncherSettings>(
        builder: (context, settings) {
          // BlocBuilder<AppsCubit> is intentionally NOT wrapping this Scaffold.
          // AppsCubit emits on every notification badge push, so wrapping the
          // whole tree would rebuild DragLayer, the touch listener, and every
          // AndroidView host view subtree on each badge event. Instead, each
          // leaf that actually consumes appsState subscribes locally.
          return Scaffold(
            backgroundColor: Colors.transparent,
            extendBody: true,
            body: Stack(
              children: [
                // Workspace subtree sits under EditModeScope so its
                // HomeWidgetSlot / HomeWidgetStackView short-circuit their
                // AndroidViews while edit mode is active, freeing each
                // appWidgetId for the overlay below to mount its own host
                // views. The overlay is NOT inside this scope.
                EditModeScope(
                  active: _editMode,
                  child: DragLayer(
                    dragController: _dragController,
                    iconShape: settings.iconShape,
                    pageController: _pageController,
                    child: WorkspaceTouchListener(
                      settings: settings,
                      dragController: _dragController,
                      onDoubleTap: () =>
                          _handleGesture(settings.doubleTapAction),
                      onSwipeUp: () => _handleGesture(settings.swipeUpAction),
                      onSwipeDown: () =>
                          _handleGesture(settings.swipeDownAction),
                      onLongPress: _enterEditMode,
                      child: Column(
                        children: [
                          SizedBox(
                              height: MediaQuery.of(context).padding.top + 8),
                          Expanded(
                            child: Visibility(
                              // Reveal workspace when dragging from drawer so
                              // drop targets are reachable behind the drawer.
                              // Hidden in edit mode so the wallpaper shows
                              // through behind the One UI–style overlay.
                              visible:
                                  (!_drawerOpen || _drawerDraggingToHome) &&
                                      !_editMode,
                              maintainState: true,
                              maintainAnimation: true,
                              maintainSize: true,
                              child: BlocBuilder<AppsCubit, AppsState>(
                                builder: (context, appsState) => WorkspaceView(
                                  dragController: _dragController,
                                  settings: settings,
                                  badgeCounts: appsState.badgeCounts,
                                  onAppTap: (app) => LauncherService.launchApp(
                                      app.packageName),
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
                          ),
                          if (settings.showDock)
                            Visibility(
                              visible:
                                  (!_drawerOpen || _drawerDraggingToHome) &&
                                      !_editMode,
                              maintainState: true,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: 12,
                                  right: 12,
                                  bottom:
                                      MediaQuery.of(context).padding.bottom +
                                          12,
                                ),
                                child: BlocBuilder<AppsCubit, AppsState>(
                                  builder: (context, appsState) => BlocBuilder<
                                      WorkspaceCubit, WorkspaceState>(
                                    buildWhen: (prev, next) =>
                                        prev.folders != next.folders,
                                    builder: (context, workspaceState) =>
                                        HotseatView(
                                      apps: _resolveDockItems(
                                        appsState,
                                        workspaceState,
                                        settings,
                                      ),
                                      settings: settings,
                                      badgeCounts: appsState.badgeCounts,
                                      dragController: _dragController,
                                      onSwipeUp: () => _handleGesture(
                                          settings.swipeUpAction),
                                      onAppTap: (app) =>
                                          LauncherService.launchApp(
                                              app.packageName),
                                      onAppLongPress: (app) =>
                                          _showAppInfoTooltip(app, Offset.zero),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_drawerOpen)
                  AllAppsContainer(
                    settings: settings,
                    dragController: _dragController,
                    onDismiss: _closeDrawer,
                    onAppTap: (app) {
                      _closeDrawer();
                      LauncherService.launchApp(app.packageName);
                    },
                    onAddToHome: _addAppToHomeScreen,
                    onDragToHome: () {
                      setState(() => _drawerDraggingToHome = true);
                      _navigateToBestDragPage();
                    },
                    onDragCancelled: () =>
                        setState(() => _drawerDraggingToHome = false),
                  ),
                if (_editMode)
                  EditModeOverlay(
                    settings: settings,
                    onDismiss: _exitEditMode,
                    onWallpaper: () {
                      _exitEditMode();
                      LauncherService.changeWallpaper();
                    },
                    onThemes: () {
                      _exitEditMode();
                      _openThemes();
                    },
                    onWidgets: () {
                      _exitEditMode();
                      _openWidgetPicker();
                    },
                    onSettings: () {
                      _exitEditMode();
                      _openSettings();
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<DockItem?> _resolveDockItems(
    AppsState appsState,
    WorkspaceState workspaceState,
    LauncherSettings settings,
  ) {
    final slotCount = _effectiveDockSlots(settings);
    final refs = _resolveDockRefs(appsState, settings).take(slotCount);
    final items = refs.map<DockItem?>((ref) {
      if (ref.isEmpty) return null;
      if (_isDockFolderRef(ref)) {
        final folderId = _folderIdFromDockRef(ref);
        final folder = workspaceState.folders[folderId];
        if (folder == null) return null;
        return DockFolderItem(
          folderId: folderId,
          folder: _resolveFolderIcons(folder, appsState),
        );
      }
      final app = appsState.apps.where((a) => a.packageName == ref).firstOrNull;
      return app == null ? null : DockAppItem(app);
    }).toList();
    return items;
  }

  List<String> _resolveDockRefs(
      AppsState appsState, LauncherSettings settings) {
    if (settings.dockPackages.isNotEmpty) {
      // Preserve slot positions: empty-string entries become null so the dock
      // displays an empty slot rather than shifting subsequent apps left.
      return List<String>.from(settings.dockPackages);
    }
    const defaults = [
      'com.android.dialer',
      'com.android.contacts',
      'com.android.messaging',
      'com.android.chrome',
      'com.android.camera2',
    ];
    final pinned =
        appsState.apps.where((a) => defaults.contains(a.packageName)).toList();
    final resolved = pinned.isEmpty
        ? appsState.apps.take(settings.dockSize).toList()
        : pinned;
    return resolved.map((a) => a.packageName).toList();
  }

  int _effectiveDockSlots(LauncherSettings settings) {
    return settings.dockSize.clamp(0, settings.gridColumns).toInt();
  }

  bool _isDockFolderRef(String ref) => ref.startsWith(kDockFolderPrefix);

  String _folderIdFromDockRef(String ref) =>
      ref.substring(kDockFolderPrefix.length);

  WorkspaceItemInfo _dockRefToWorkspaceItem(
    String ref,
    AppsState appsState,
  ) {
    final app = appsState.apps.where((a) => a.packageName == ref).firstOrNull;
    return WorkspaceItemInfo(
      id: app?.id ?? ref.hashCode,
      itemType: ItemType.application,
      packageName: ref,
      componentName: app?.appComponentName ?? ref,
      title: app?.name ?? ref,
      icon: app?.icon,
    );
  }

  void _normalizeDockForCurrentState() {
    if (!mounted || _normalizingDock) return;
    final settings = context.read<SettingsCubit>().state;
    final appsState = context.read<AppsCubit>().state;
    if (appsState.apps.isEmpty) return;

    final capacity = _effectiveDockSlots(settings);
    final refs = _resolveDockRefs(appsState, settings);
    final hasOverflow = refs.length > capacity;
    final visibleRefs = refs.take(capacity).toList();
    final overflowRefs = refs.skip(capacity).where((ref) => ref.isNotEmpty);
    final workspace = context.read<WorkspaceCubit>();
    final dockFolderRef = refs
        .where((ref) =>
            _isDockFolderRef(ref) &&
            workspace.state.folders.containsKey(_folderIdFromDockRef(ref)))
        .firstOrNull;
    final overflowAppRefs =
        overflowRefs.where((ref) => !_isDockFolderRef(ref)).toList();

    if (dockFolderRef != null && capacity > 0 && hasOverflow) {
      if (!visibleRefs.contains(dockFolderRef)) {
        final displacedRef = visibleRefs.isEmpty ? '' : visibleRefs.last;
        if (displacedRef.isNotEmpty && !_isDockFolderRef(displacedRef)) {
          overflowAppRefs.insert(0, displacedRef);
        }
        if (visibleRefs.isEmpty) {
          visibleRefs.add(dockFolderRef);
        } else {
          visibleRefs[visibleRefs.length - 1] = dockFolderRef;
        }
      }
      final overflowItems = overflowAppRefs
          .map((ref) => _dockRefToWorkspaceItem(ref, appsState))
          .toList();
      workspace.addItemsToFolder(
        _folderIdFromDockRef(dockFolderRef),
        overflowItems,
      );
    } else if (overflowAppRefs.isNotEmpty) {
      final overflowItems = overflowAppRefs
          .map((ref) => _dockRefToWorkspaceItem(ref, appsState))
          .toList();
      workspace.createFolderForItems(
        overflowItems,
        settings.gridColumns,
        settings.gridRows,
      );
    }

    final shouldClampDockSize = settings.dockSize != capacity;
    final shouldTrimPackages = hasOverflow || settings.dockPackages.isEmpty;
    if (!shouldClampDockSize && !hasOverflow) return;

    _normalizingDock = true;
    final nextPackages =
        shouldTrimPackages ? visibleRefs : settings.dockPackages;
    context.read<SettingsCubit>().update(
          settings.copyWith(
            dockSize: capacity,
            dockPackages: nextPackages,
          ),
        );
    _normalizingDock = false;
  }

  FolderInfo _resolveFolderIcons(FolderInfo folder, AppsState appsState) {
    final resolved = folder.contents.map((item) {
      if (item.icon != null) return item;
      final live = appsState.apps
          .where((a) => a.packageName == item.packageName)
          .firstOrNull;
      if (live == null) return item;
      return WorkspaceItemInfo(
        id: item.id,
        itemType: item.itemType,
        packageName: item.packageName,
        componentName: item.componentName ?? live.appComponentName,
        title: item.title ?? live.name,
        icon: live.icon,
      );
    }).toList();
    return FolderInfo(
      id: folder.id,
      folderTitle: folder.folderTitle,
      contents: resolved,
      cellX: folder.cellX,
      cellY: folder.cellY,
      screenId: folder.screenId,
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
    double left = (iconCenter.dx - tooltipW / 2)
        .clamp(8.0, screenSize.width - tooltipW - 8);
    double top = (iconCenter.dy - tooltipH - 12)
        .clamp(8.0, screenSize.height - tooltipH - 8);

    return Stack(
      children: [
        // Tap-outside dismisses
        Positioned.fill(
            child: GestureDetector(
                onTap: onDismiss, behavior: HitTestBehavior.translucent)),
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
                boxShadow: [
                  BoxShadow(
                      color: Colors.black45,
                      blurRadius: 8,
                      offset: Offset(0, 3))
                ],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onAppInfo,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.info_outline,
                        color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Text(app.name,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        overflow: TextOverflow.ellipsis),
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
