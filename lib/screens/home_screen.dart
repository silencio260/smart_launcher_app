import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_info.dart';
import '../models/folder_info.dart';
import '../models/item_info.dart';
import '../models/launcher_feature.dart';
import '../models/launcher_widget_info.dart';
import '../models/launcher_settings.dart';
import '../models/launcher_state.dart' as ls;
import '../models/workspace_item_info.dart';
import '../services/after_call_service.dart';
import '../services/install_assistant_service.dart';
import '../services/default_layout_seeder.dart';
import '../services/feature_launch_dispatcher.dart';
import '../services/launcher_service.dart';
import '../services/icons/decoded_icon_cache.dart';
import '../utils/debug_flags.dart';
import '../utils/drawer_perf.dart';
import '../state/apps_cubit.dart';
import '../state/launcher_cubit.dart';
import '../state/launcher_feature_cubit.dart';
import '../state/search_cubit.dart';
import '../state/settings_cubit.dart';
import '../state/workspace_cubit.dart';
import '../widgets/allapps/all_apps_container.dart';
import '../widgets/dock/hotseat_view.dart';
import '../widgets/edit_mode/edit_mode_overlay.dart';
import '../widgets/edit_mode/edit_mode_scope.dart';
import '../widgets/drag/drag_layer.dart';
import '../widgets/workspace/route_coverage_scope.dart';
import '../widgets/workspace/home_widget_stack_view.dart';
import '../widgets/workspace/workspace_touch_listener.dart';
import '../widgets/workspace/workspace_view.dart';
import '../services/drag/drag_controller.dart';
import '../services/gestures/widget_resize_gesture_guard.dart';
import 'search_overlay_screen.dart';
import 'settings/general_settings_screen.dart';
import 'settings/settings_root_screen.dart';
import 'settings/widget_picker_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, RouteAware {
  final _dragController = DragController();
  final _routeCovered = ValueNotifier<bool>(false);
  OverlayEntry? _appInfoTooltip;
  bool _drawerOpen = false;
  bool _drawerDraggingToHome = false;
  bool _editMode = false;
  bool _didEnsureDefaultClock = false;
  bool _didSeedDefaultLayout = false;
  bool _didSeedFeatureApps = false;
  bool _defaultSeedResolved = false;
  bool _normalizingDock = false;
  PageController? _pageController;
  Timer? _drawerPrewarmTimer;
  bool _drawerPrewarmRunning = false;
  int _drawerPrewarmGeneration = 0;
  // Target slot for a pending "Create stack" / "Edit stack add" picker flow.
  // Set when the user triggers the picker from a widget action menu; consumed
  // (and cleared) once the picker delivers the picked LauncherWidgetInfo.
  ({int page, int slot})? _pendingStackTarget;

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
      context.read<AppsCubit>().startAppInstallListening();
      // Keep the native package detector's flag in lockstep with the Dart toggle,
      // so the Application's startup registration can't drift after a reinstall.
      InstallAssistantService.setEnabled(
        context
            .read<LauncherFeatureSettingsCubit>()
            .state
            .installUninstallAssistantEnabled,
      );
      // An after-call overlay tap (cold start) leaves an action waiting natively.
      _consumeAfterCallAction();
      // An install/uninstall overlay tap (add-to-home, hide, cleanup, disable)
      // is stashed natively; drain it the same way.
      _consumeInstallAssistantAction();
      _maybePromptDefaultLauncher();
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      homeRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    // A route was pushed on top of the home screen (Settings, widget picker,
    // etc.). Flip coverage so HomeWidgetSlot drops its AndroidViews — keeping
    // them alive while covered keeps hybrid composition costing per-frame work
    // and janks scroll on the page on top.
    _routeCovered.value = true;
    if (DebugFlags.routeCoverageLogs) {
      debugPrint('DrawerPerf RouteCoverage covered=true');
    }
  }

  @override
  void didPopNext() {
    // The route on top was popped; we're visible again. Re-mount widgets.
    _routeCovered.value = false;
    if (DebugFlags.routeCoverageLogs) {
      debugPrint('DrawerPerf RouteCoverage covered=false');
    }
  }

  @override
  void dispose() {
    homeRouteObserver.unsubscribe(this);
    _routeCovered.dispose();
    _drawerPrewarmTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _dragController.removeListener(_onDragChange);
    _dragController.dispose();
    super.dispose();
  }

  DateTime _lastResumeReload = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Always refresh badges — cheap, and notification counts go stale fast.
    context.read<AppsCubit>().refreshBadges();
    // A warm resume can be an after-call overlay tap; drain any pending action.
    _consumeAfterCallAction();
    // …or an install/uninstall overlay tap chosen while we were backgrounded.
    _consumeInstallAssistantAction();
    // Full app list reload is expensive (icon decode for every package). The
    // Android side fires PACKAGE_ADDED/REMOVED intents into the launcher
    // service, so a periodic resume-reload is only a fallback. Cap it to
    // once every 30s so quick app-switches don't hammer the list.
    final now = DateTime.now();
    if (now.difference(_lastResumeReload).inSeconds < 30) return;
    _lastResumeReload = now;
    context.read<AppsCubit>().loadApps();
  }

  void _openDrawer() {
    DrawerPerf.beginSession();
    DrawerPerf.event('home.openDrawer');
    context.read<AppsCubit>().setDrawerActive(true);
    setState(() => _drawerOpen = true);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      DrawerPerf.event('home.openDrawer.firstPostFrame');
    });
  }

  void _closeDrawer() {
    DrawerPerf.event('home.closeDrawer');
    context.read<AppsCubit>().setDrawerActive(false);
    setState(() {
      _drawerOpen = false;
      _drawerDraggingToHome = false;
    });
    context.read<LauncherCubit>().goToState(ls.LauncherState.normal);
    _scheduleDrawerIconPrewarm(context.read<AppsCubit>().state.apps);
    DrawerPerf.endSession();
  }

  void _enterEditMode() {
    _dismissAppInfoTooltip();
    _syncCurrentPageToVisibleWorkspacePage();
    setState(() => _editMode = true);
    // Push the same global lock per-widget resize uses, so EVERY swipe path
    // (workspace touch listener, dock GestureDetector, etc.) sees one source
    // of truth for "is the home screen in an edit-like mode?".
    WidgetResizeGestureGuard.setOverlayActive(true);
    WidgetResizeGestureGuard.onRequestDismiss = _exitEditMode;
  }

  void _syncCurrentPageToVisibleWorkspacePage() {
    final workspace = context.read<WorkspaceCubit>();
    final pageCount = workspace.state.pages.length;
    if (pageCount == 0) return;

    final rawPage = _pageController?.hasClients == true
        ? _pageController!.page ?? _pageController!.initialPage.toDouble()
        : workspace.state.currentPage.toDouble();
    final visiblePage = rawPage.round() % pageCount;
    if (workspace.state.currentPage != visiblePage) {
      workspace.setCurrentPage(visiblePage);
    }
  }

  void _exitEditMode() {
    setState(() => _editMode = false);
    WidgetResizeGestureGuard.setOverlayActive(false);
    // Only clear the dismiss hook if we own it (cell_layout may also wire
    // it for per-widget selection). Safe to null here because the overlay
    // is the only thing left holding it once we set it above.
    if (WidgetResizeGestureGuard.onRequestDismiss == _exitEditMode) {
      WidgetResizeGestureGuard.onRequestDismiss = null;
    }
  }

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
        iconPath: app.iconPath,
        launcherFeatureId: app.launcherFeatureId ??
            LauncherFeatureCatalog.idForPackage(app.packageName),
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

  static const _seededFlagKey = 'default_layout_seeded_v1';
  static const _featureSeededFlagKey = 'launcher_feature_icons_seeded_v1';
  static const _promptedDefaultLauncherKey = 'prompted_default_launcher_v1';

  // One-shot first-launch prompt to become the default home app. Skips if it's
  // already the default or the user has already been asked once.
  Future<void> _maybePromptDefaultLauncher() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_promptedDefaultLauncherKey) == true) return;
    if (await LauncherService.isDefaultLauncher()) {
      await prefs.setBool(_promptedDefaultLauncherKey, true);
      return;
    }
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set as default home app?'),
        content: const Text(
          'Make Smart Launcher your home screen so it opens when you press '
          'the home button.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Set default'),
          ),
        ],
      ),
    );
    await prefs.setBool(_promptedDefaultLauncherKey, true);
    if (accepted == true) {
      await LauncherService.requestHomeRole();
    }
  }

  // One-shot first-run seeding. Both the installed-apps list and the saved
  // workspace layout load asynchronously at startup, so this is invoked from
  // both the AppsCubit and WorkspaceCubit listeners and only commits once both
  // are ready. Existing users (who already had a saved layout before this
  // feature shipped) are detected via WorkspaceCubit.wasFreshInstall and left
  // untouched.
  Future<void> _maybeSeedDefaultLayout() async {
    if (_didSeedDefaultLayout) return;
    final workspace = context.read<WorkspaceCubit>();
    final apps = context.read<AppsCubit>().state.apps;
    if (workspace.state.pages.isEmpty || apps.isEmpty) return;
    _didSeedDefaultLayout = true;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seededFlagKey) == true) {
      _defaultSeedResolved = true;
      return;
    }
    if (!workspace.wasFreshInstall) {
      _defaultSeedResolved = true;
      await prefs.setBool(_seededFlagKey, true);
      return;
    }
    if (!mounted) return;
    DefaultLayoutSeeder.seed(
      apps: apps,
      workspace: workspace,
      settings: context.read<SettingsCubit>(),
    );
    _defaultSeedResolved = true;
    await prefs.setBool(_seededFlagKey, true);
  }

  Future<void> _maybeSeedFeatureApps() async {
    if (_didSeedFeatureApps) return;
    final workspace = context.read<WorkspaceCubit>();
    if (workspace.state.pages.isEmpty) return;
    _didSeedFeatureApps = true;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (prefs.getBool(_featureSeededFlagKey) == true) return;
    final settings = context.read<SettingsCubit>().state;
    workspace.seedLauncherFeatureApps(settings.gridColumns, settings.gridRows);
    await prefs.setBool(_featureSeededFlagKey, true);
  }

  // Strip a removed package's leftovers from the launcher: workspace icons,
  // dock entry, and hidden-apps entry. Invoked when the user taps "Clean up" on
  // the native uninstall card (delivered as a pending `cleanup:<pkg>` action).
  void _cleanupRemovedPackage(String packageName) {
    if (!mounted) return;
    final workspaceChanged =
        context.read<WorkspaceCubit>().removePackageArtifacts(packageName);
    final settings = context.read<SettingsCubit>().state;
    final nextDock =
        settings.dockPackages.where((pkg) => pkg != packageName).toList();
    final nextHidden =
        settings.hiddenApps.where((pkg) => pkg != packageName).toList();
    if (nextDock.length != settings.dockPackages.length ||
        nextHidden.length != settings.hiddenApps.length) {
      context.read<SettingsCubit>().update(
            settings.copyWith(
              dockPackages: nextDock,
              hiddenApps: nextHidden,
            ),
          );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            workspaceChanged ? 'Removed stale launcher icons' : 'Cleaned up'),
      ),
    );
  }

  // The after-call card is a native system overlay drawn over the dialer. Its
  // app-specific actions (vault, note) re-enter the launcher with the action
  // stashed natively; we drain it here on launch and on resume.
  Future<void> _consumeAfterCallAction() async {
    final action = await AfterCallService.consumePendingAction();
    if (!mounted || action == null) return;
    switch (action) {
      case 'vault':
        FeatureLaunchDispatcher.openFeature(context, 'file_locker');
      case 'note':
        _openSearch();
    }
  }

  // The install/uninstall card is a native system overlay. Actions that mutate
  // launcher state are stashed natively and applied here once Flutter is alive.
  Future<void> _consumeInstallAssistantAction() async {
    final action = await InstallAssistantService.consumePendingAction();
    if (!mounted || action == null || action.isEmpty) return;

    if (action == 'disable') {
      final cubit = context.read<LauncherFeatureSettingsCubit>();
      await InstallAssistantService.setEnabled(false);
      if (!mounted) return;
      cubit.update(
        cubit.state.copyWith(installUninstallAssistantEnabled: false),
      );
      return;
    }

    final separator = action.indexOf(':');
    if (separator <= 0 || separator == action.length - 1) return;
    final verb = action.substring(0, separator);
    final packageName = action.substring(separator + 1);

    switch (verb) {
      case 'add_home':
        final app = await _resolveInstalledApp(packageName);
        if (!mounted || app == null) return;
        _addAppToHomeScreen(app);
      case 'hide':
        final settings = context.read<SettingsCubit>().state;
        final hidden = settings.hiddenApps.toSet()..add(packageName);
        context.read<SettingsCubit>().update(
              settings.copyWith(hiddenApps: hidden.toList()..sort()),
            );
      case 'cleanup':
        _cleanupRemovedPackage(packageName);
    }
  }

  Future<AppInfo?> _resolveInstalledApp(String packageName) async {
    final appsCubit = context.read<AppsCubit>();
    var app = appsCubit.state.appsByPackage[packageName];
    if (app != null) return app;

    await appsCubit.loadApps(forceFull: true);
    if (!mounted) return null;
    app = appsCubit.state.appsByPackage[packageName];
    return app;
  }

  void _handleGesture(GestureAction action) {
    // Single choke point. WidgetResizeGestureGuard.isResizing is true if ANY
    // edit-like mode is active: per-widget resize selection, an active touch
    // on a resize handle, OR the global home-screen EditModeOverlay. In all
    // three cases the only allowed effect of a swipe/double-tap is to
    // dismiss the active mode — never to fire its assigned action.
    if (WidgetResizeGestureGuard.isResizing) {
      WidgetResizeGestureGuard.requestDismiss();
      return;
    }
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
        FeatureLaunchDispatcher.launchPackage(context, 'com.android.camera2');
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
            BlocProvider.value(
                value: context.read<LauncherFeatureSettingsCubit>()),
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
            BlocProvider.value(
                value: context.read<LauncherFeatureSettingsCubit>()),
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
            BlocProvider.value(
                value: context.read<LauncherFeatureSettingsCubit>()),
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
            BlocProvider.value(
                value: context.read<LauncherFeatureSettingsCubit>()),
            BlocProvider.value(value: context.read<AppsCubit>()),
            BlocProvider.value(value: context.read<WorkspaceCubit>()),
          ],
          child: WidgetPickerScreen(onWidgetAdded: _addWidgetToHomeScreen),
        ),
      ),
    );
  }

  void _openWidgetPickerForStack(int page, int slot) {
    _pendingStackTarget = (page: page, slot: slot);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<SettingsCubit>()),
            BlocProvider.value(value: context.read<AppsCubit>()),
            BlocProvider.value(value: context.read<WorkspaceCubit>()),
          ],
          child: WidgetPickerScreen(
            onWidgetPicked: _mergePickedWidgetIntoStack,
          ),
        ),
      ),
    ).whenComplete(() {
      // Clear if the user dismissed without picking.
      _pendingStackTarget = null;
    });
  }

  void _mergePickedWidgetIntoStack(LauncherWidgetInfo picked) {
    final target = _pendingStackTarget;
    _pendingStackTarget = null;
    if (target == null) return;
    final workspace = context.read<WorkspaceCubit>();
    workspace.addWidgetToStackSlot(target.page, target.slot, picked);
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
          final featureId = app.launcherFeatureId ??
              LauncherFeatureCatalog.idForPackage(app.packageName);
          if (featureId != null) {
            FeatureLaunchDispatcher.openFeature(context, featureId);
          } else {
            LauncherService.openAppSettings(app.packageName);
          }
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
              (!_didEnsureDefaultClock || !_didSeedDefaultLayout) &&
              curr.pages.isNotEmpty,
          listener: (context, state) {
            _ensureDefaultClockWidget(
              state,
              context.read<SettingsCubit>().state,
            );
            _maybeSeedDefaultLayout();
            _maybeSeedFeatureApps();
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
        BlocListener<SettingsCubit, LauncherSettings>(
          listenWhen: (prev, next) =>
              prev.drawerIconSize != next.drawerIconSize,
          listener: (context, settings) {
            _scheduleDrawerIconPrewarm(
              context.read<AppsCubit>().state.apps,
              settings: settings,
            );
          },
        ),
        BlocListener<AppsCubit, AppsState>(
          listenWhen: (prev, next) => prev.apps != next.apps,
          listener: (_, state) {
            _maybeSeedDefaultLayout();
            _maybeSeedFeatureApps();
            _normalizeDockForCurrentState();
            _scheduleDrawerIconPrewarm(state.apps);
          },
        ),
      ],
      child: RouteCoverageScope(
        notifier: _routeCovered,
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
                                // No BlocBuilder<AppsCubit> here — leaves
                                // (BubbleTextView/FolderIconView via BlocSelector
                                // in CellLayoutView) subscribe individually, so
                                // notification badge updates don't rebuild the
                                // entire PageView + AndroidView subtree.
                                child: WorkspaceView(
                                  dragController: _dragController,
                                  settings: settings,
                                  onAppTap: (app) =>
                                      FeatureLaunchDispatcher.launch(
                                          context, app),
                                  onAppLongPress: (app, page, slot, center) =>
                                      _showAppInfoTooltip(app, center),
                                  onBackgroundLongPress: _enterEditMode,
                                  onPickWidgetForStack:
                                      _openWidgetPickerForStack,
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
                              ValueListenableBuilder<(int, int)?>(
                                valueListenable:
                                    HomeWidgetStackView.suppressedAt,
                                builder: (context, suppressedStack, child) {
                                  return Visibility(
                                    visible: suppressedStack == null &&
                                        (!_drawerOpen ||
                                            _drawerDraggingToHome) &&
                                        !_editMode,
                                    maintainState: true,
                                    child: child!,
                                  );
                                },
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    left: 12,
                                    right: 12,
                                    bottom:
                                        MediaQuery.of(context).padding.bottom +
                                            12,
                                  ),
                                  // Outer selector watches only the apps list
                                  // (not loading / badge fields) so badge pushes
                                  // and loading toggles don't rebuild the dock.
                                  child: BlocSelector<AppsCubit, AppsState,
                                      List<AppInfo>>(
                                    selector: (s) => s.apps,
                                    builder: (context, _) {
                                      final appsState =
                                          context.read<AppsCubit>().state;
                                      return BlocSelector<
                                          WorkspaceCubit,
                                          WorkspaceState,
                                          Map<String, FolderInfo>>(
                                        selector: (s) => s.folders,
                                        builder: (context, _) {
                                          final workspaceState = context
                                              .read<WorkspaceCubit>()
                                              .state;
                                          return HotseatView(
                                            apps: _resolveDockItems(
                                              appsState,
                                              workspaceState,
                                              settings,
                                            ),
                                            settings: settings,
                                            dragController: _dragController,
                                            onSwipeUp: () => _handleGesture(
                                                settings.swipeUpAction),
                                            onAppTap: (app) =>
                                                FeatureLaunchDispatcher.launch(
                                                    context, app),
                                            onAppLongPress: (app, center) =>
                                                _showAppInfoTooltip(
                                                    app, center),
                                          );
                                        },
                                      );
                                    },
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
                        FeatureLaunchDispatcher.launch(context, app);
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
                      onPageSelected: (page) {
                        context.read<WorkspaceCubit>().setCurrentPage(page);
                        _pageController?.jumpToPage(page);
                      },
                    ),
                ],
              ),
            );
          },
        ),
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
    final byPackage = appsState.appsByPackage;
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
      final app = byPackage[ref];
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
    final app = appsState.appsByPackage[ref];
    return WorkspaceItemInfo(
      id: app?.id ?? ref.hashCode,
      itemType: ItemType.application,
      packageName: ref,
      componentName: app?.appComponentName ?? ref,
      title: app?.name ?? ref,
      icon: app?.icon,
      iconPath: app?.iconPath,
      launcherFeatureId:
          app?.launcherFeatureId ?? LauncherFeatureCatalog.idForPackage(ref),
    );
  }

  void _normalizeDockForCurrentState() {
    if (!mounted || _normalizingDock) return;
    // On a fresh install, hold off normalizing until the default-layout seed has
    // committed — otherwise we'd resolve the legacy hardcoded dock defaults and
    // create a throwaway overflow folder that the seed then discards.
    if (context.read<WorkspaceCubit>().wasFreshInstall &&
        !_defaultSeedResolved) {
      return;
    }
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

  void _scheduleDrawerIconPrewarm(
    List<AppInfo> apps, {
    LauncherSettings? settings,
  }) {
    if (!mounted || apps.isEmpty) return;
    final effectiveSettings = settings ?? context.read<SettingsCubit>().state;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final targetPx =
        (effectiveSettings.drawerIconSize * dpr).ceil().clamp(1, 512).toInt();
    final hidden = effectiveSettings.hiddenApps.toSet();
    final visibleApps = hidden.isEmpty
        ? apps
        : apps
            .where((app) => !hidden.contains(app.packageName))
            .toList(growable: false);
    if (visibleApps.isEmpty) return;

    final generation = ++_drawerPrewarmGeneration;
    _drawerPrewarmTimer?.cancel();
    _drawerPrewarmTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _drawerPrewarmRunning || _drawerOpen) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _drawerPrewarmRunning ||
            _drawerOpen ||
            generation != _drawerPrewarmGeneration) {
          return;
        }
        _drawerPrewarmRunning = true;
        _precacheDrawerIcons(
          visibleApps,
          targetPx,
          generation: generation,
        ).whenComplete(() {
          _drawerPrewarmRunning = false;
        });
      });
    });
  }

  Future<void> _precacheDrawerIcons(
    List<AppInfo> apps,
    int targetPx, {
    required int generation,
  }) async {
    final sw = Stopwatch()..start();
    DrawerPerf.event('drawer.prewarm.start',
        extra: {'apps': apps.length, 'targetPx': targetPx, 'gen': generation});
    var fileCount = 0;
    for (final app in apps) {
      if (!mounted) return;
      if (!_shouldContinueDrawerPrewarm(generation)) {
        DrawerPerf.event('drawer.prewarm.cancelled', extra: {
          'phase': 'precache',
          'processed': fileCount,
          'durationMs': sw.elapsedMilliseconds,
        });
        return;
      }
      final iconPath = app.iconPath;
      if (iconPath == null || iconPath.isEmpty) continue;
      try {
        final provider = ResizeImage.resizeIfNeeded(
          targetPx,
          targetPx,
          FileImage(File(iconPath)),
        );
        await precacheImage(provider, context);
      } catch (_) {
        // A missing cache file just falls through to ShapedIcon's fallback.
      }
      fileCount += 1;
      if (fileCount % 8 == 0) {
        DrawerPerf.event('drawer.prewarm.batch', extra: {
          'processed': fileCount,
          'durationMs': sw.elapsedMilliseconds,
        });
        await SchedulerBinding.instance.endOfFrame;
      }
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }
    DrawerPerf.event('drawer.prewarm.precacheDone', extra: {
      'processed': fileCount,
      'durationMs': sw.elapsedMilliseconds,
    });

    if (!_shouldContinueDrawerPrewarm(generation)) {
      DrawerPerf.event('drawer.prewarm.cancelled', extra: {
        'phase': 'beforeDecode',
        'durationMs': sw.elapsedMilliseconds,
      });
      return;
    }
    await DecodedIconCache.instance.prewarm(
      apps,
      targetPx: targetPx,
      limit: apps.length,
      concurrency: 1,
      pauseBetweenDecodes: const Duration(milliseconds: 6),
      shouldContinue: () => _shouldContinueDrawerPrewarm(generation),
    );
    DrawerPerf.event('drawer.prewarm.end', extra: {
      'apps': apps.length,
      'durationMs': sw.elapsedMilliseconds,
    });
  }

  bool _shouldContinueDrawerPrewarm(int generation) =>
      mounted &&
      !_drawerOpen &&
      !_drawerDraggingToHome &&
      generation == _drawerPrewarmGeneration;

  FolderInfo _resolveFolderIcons(FolderInfo folder, AppsState appsState) {
    final byPackage = appsState.appsByPackage;
    final resolved = folder.contents.map((item) {
      final live = byPackage[item.packageName];
      if (live == null) return item;
      return WorkspaceItemInfo(
        id: item.id,
        itemType: item.itemType,
        packageName: item.packageName,
        componentName: item.componentName ?? live.appComponentName,
        title: item.title ?? live.name,
        icon: live.icon,
        iconPath: live.iconPath,
        launcherFeatureId: item.launcherFeatureId ?? live.launcherFeatureId,
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
