import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_launcher_app/core/models/app_info.dart';
import 'package:smart_launcher_app/core/models/folder_info.dart';
import 'package:smart_launcher_app/core/models/item_info.dart';
import 'package:smart_launcher_app/core/models/launcher_feature.dart';
import 'package:smart_launcher_app/core/models/launcher_widget_info.dart';
import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/core/models/launcher_state.dart' as ls;
import 'package:smart_launcher_app/core/models/workspace_item_info.dart';
import 'package:smart_launcher_app/core/storage/mini_app_repositories.dart';
import 'package:smart_launcher_app/features/after_call/data/after_call_service.dart';
import 'package:smart_launcher_app/features/install_assistant/data/install_assistant_service.dart';
import 'package:smart_launcher_app/features/home/data/default_layout_seeder.dart';
import 'package:smart_launcher_app/features/home/data/seed_flags.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/launcher_initializing_view.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/restore_layout_banner.dart';
import 'package:smart_launcher_app/core/platform/feature_launch_dispatcher.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/core/icons/decoded_icon_cache.dart';
import 'package:smart_launcher_app/core/utils/debug_flags.dart';
import 'package:smart_launcher_app/core/utils/drawer_perf.dart';
import 'package:smart_launcher_app/features/apps/presentation/bloc/apps_cubit.dart';
import 'package:smart_launcher_app/features/home/presentation/bloc/launcher_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/launcher_feature_cubit.dart';
import 'package:smart_launcher_app/features/search/presentation/bloc/search_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:smart_launcher_app/features/home/presentation/bloc/workspace_cubit.dart';
import 'package:smart_launcher_app/features/app_drawer/presentation/widgets/allapps/all_apps_container.dart';
import 'package:smart_launcher_app/core/widgets/app_menu/app_context_menu.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/dock/hotseat_view.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/edit_mode/edit_mode_overlay.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/edit_mode/edit_mode_scope.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/drag/drag_layer.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/workspace/route_coverage_scope.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/workspace/home_widget_stack_view.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/workspace/home_sections.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/workspace/workspace_touch_listener.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/workspace/workspace_view.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/dock/smart_search_pill.dart';
import 'package:smart_launcher_app/features/home/presentation/drag/drag_controller.dart';
import 'package:smart_launcher_app/features/home/presentation/gestures/widget_resize_gesture_guard.dart';
import 'package:smart_launcher_app/features/search/presentation/screens/search_overlay_screen.dart';
import 'package:smart_launcher_app/features/search/presentation/screens/smart_search_screen.dart';
import 'package:smart_launcher_app/features/after_call/presentation/screens/after_call_settings_screen.dart';
import 'package:smart_launcher_app/features/good_morning/presentation/screens/good_morning_screen.dart';
import 'package:smart_launcher_app/features/discover/presentation/screens/discover_page.dart';
import 'package:smart_launcher_app/features/app_library/presentation/screens/app_library_page.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/launcher_themes_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/settings_appearance.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/settings_root_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/wallpaper_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/widget_picker_screen.dart';
import 'package:smart_launcher_app/features/home/presentation/screens/themes/ios_home_view.dart';
import 'package:smart_launcher_app/features/home/presentation/screens/themes/minimal_home_view.dart';
import 'package:smart_launcher_app/features/onboarding/data/onboarding_store.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/widgets/default_launcher_nudge.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.firstRun = false});

  /// True only for the HomeScreen pushed straight after the onboarding flow
  /// (genuine fresh install or the Dev View "Simulate fresh install"). Drives
  /// the one-shot "Setting up your launcher" cover, which stays up until the
  /// default layout has been seeded — then reveals the populated home. A warm
  /// start (onboarding already completed) uses `firstRun: false` and never
  /// shows the cover.
  final bool firstRun;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, RouteAware {
  final _dragController = DragController();
  final _routeCovered = ValueNotifier<bool>(false);
  OverlayEntry? _appInfoTooltip;
  // Persistent "set as default home app" reminder, shown after onboarding was
  // skipped. Lives in the root overlay (like _appInfoTooltip) but is hidden
  // whenever the drawer / edit mode / a pushed route covers the home surface.
  OverlayEntry? _defaultNudge;
  bool _defaultNudgeEligible = false;
  bool _drawerOpen = false;
  bool _drawerDraggingToHome = false;
  bool _editMode = false;
  bool _didEnsureDefaultClock = false;
  bool _didSeedDefaultLayout = false;
  bool _didSeedFeatureApps = false;
  bool _defaultSeedResolved = false;
  bool _normalizingDock = false;
  // First-run "Setting up your launcher" cover. Shown from mount until the
  // default layout has been seeded and apps have loaded, then dismissed to
  // reveal home. A 10s failsafe (see [_initFailsafeTimer]) reveals home anyway
  // if seeding somehow stalls, and flips [_seedTimedOut] so the home surfaces a
  // "Restore home screen layout" action under the set-as-default nudge.
  bool _initializing = false;
  bool _seedTimedOut = false;
  Timer? _initFailsafeTimer;
  static const _initFailsafe = Duration(seconds: 10);
  PageController? _pageController;
  // Dock + Smart-search pill "chrome": faded out as the pager scrolls into a
  // flanking special page (Discover / App Library). Driven by WorkspaceView at
  // scroll cadence via a ValueNotifier so the pager subtree never rebuilds.
  final ValueNotifier<double> _chromeOpacity = ValueNotifier<double>(1.0);
  // Horizontal slide fraction (-1..1) for the chrome so it travels off-screen
  // with the home content as a special page slides in (no "floating" dissolve).
  final ValueNotifier<double> _chromeSlide = ValueNotifier<double>(0.0);
  final ValueNotifier<HomeSection> _activeSection =
      ValueNotifier<HomeSection>(HomeSection.home);
  // Measured height of the bottom chrome band (dock + pill + safe area). Fed
  // back as WorkspaceView.homeBottomInset so home pages reserve exactly that
  // much space and the bottom grid row isn't hidden behind the dock.
  final GlobalKey _bottomChromeKey = GlobalKey();
  double _bottomChromeHeight = 132;
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
    // Fresh install / simulate: cover the home with the setup screen until the
    // layout is seeded, with a hard failsafe so we never get stuck on it.
    _initializing = widget.firstRun;
    if (_initializing) {
      _initFailsafeTimer = Timer(_initFailsafe, _onInitTimeout);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<AppsCubit>()
          .setBadgesEnabled(
            context.read<SettingsCubit>().state.notificationBadgesEnabled,
          );
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
      _consumeFeatureRoute();
      // An install/uninstall overlay tap (add-to-home, hide, cleanup, disable)
      // is stashed natively; drain it the same way.
      _consumeInstallAssistantAction();
      ClockRepository().rescheduleEnabledAlarms();
      _evaluateDefaultNudgeEligibility();
      // Seed from the CURRENT cubit state, not just future emits. The
      // BlocListeners below only fire on changes after they subscribe, so if
      // apps + workspace already settled before this mounted (e.g. after the
      // Dev "Simulate fresh install" reload, or a fast cold start), the seed
      // would otherwise never run and the first-run cover would hang until the
      // failsafe. These calls are idempotent (guarded by _did* flags).
      if (!mounted) return;
      _ensureDefaultClockWidget(
        context.read<WorkspaceCubit>().state,
        context.read<SettingsCubit>().state,
      );
      _maybeSeedDefaultLayout();
      _maybeSeedFeatureApps();
      _maybeRevealHome();
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
    _refreshDefaultNudge();
    if (DebugFlags.routeCoverageLogs) {
      debugPrint('DrawerPerf RouteCoverage covered=true');
    }
  }

  @override
  void didPopNext() {
    // The route on top was popped; we're visible again. Re-mount widgets.
    _routeCovered.value = false;
    _refreshDefaultNudge();
    if (DebugFlags.routeCoverageLogs) {
      debugPrint('DrawerPerf RouteCoverage covered=false');
    }
  }

  @override
  void dispose() {
    homeRouteObserver.unsubscribe(this);
    _routeCovered.dispose();
    _initFailsafeTimer?.cancel();
    _drawerPrewarmTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _dragController.removeListener(_onDragChange);
    _dragController.dispose();
    _chromeOpacity.dispose();
    _chromeSlide.dispose();
    _activeSection.dispose();
    _defaultNudge?.remove();
    _defaultNudge = null;
    super.dispose();
  }

  DateTime _lastResumeReload = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // The home role may have been granted from the system dialog while we were
    // away; re-evaluate whether the "set as default" nudge still applies.
    _evaluateDefaultNudgeEligibility();
    // Always refresh badges — cheap, and notification counts go stale fast.
    context.read<AppsCubit>().refreshBadges();
    // A warm resume can be an after-call overlay tap; drain any pending action.
    _consumeAfterCallAction();
    _consumeFeatureRoute();
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
    _refreshDefaultNudge();
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
    _refreshDefaultNudge();
    context.read<LauncherCubit>().goToState(ls.LauncherState.normal);
    _scheduleDrawerIconPrewarm(context.read<AppsCubit>().state.apps);
    DrawerPerf.endSession();
  }

  void _enterEditMode() {
    _dismissAppInfoTooltip();
    _syncCurrentPageToVisibleWorkspacePage();
    setState(() => _editMode = true);
    _refreshDefaultNudge();
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
    // rawPage is in pager (controller) space; convert back to a home index.
    final visiblePage =
        (rawPage.round() - _leadingCount()).clamp(0, pageCount - 1).toInt();
    if (workspace.state.currentPage != visiblePage) {
      workspace.setCurrentPage(visiblePage);
    }
  }

  void _exitEditMode() {
    setState(() => _editMode = false);
    _refreshDefaultNudge();
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
        _toControllerPage(placement.page),
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
        launcherFeatureId: LauncherFeatureCatalog.idForApp(app),
        screenId: 0,
      ),
      settings.gridColumns,
      settings.gridRows,
    );

    // Navigate to the page where the app was placed.
    final page = placement.page;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageController?.animateToPage(
        _toControllerPage(page),
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
        _toControllerPage(page),
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

  static const _seededFlagKey = kDefaultLayoutSeededFlag;
  static const _featureSeededFlagKey = kFeatureIconsSeededFlag;

  // Resolves whether the "set as default" nudge should ever appear: only when
  // the user hasn't dismissed it and we don't already hold the home role. The
  // first-launch prompt itself now lives in the onboarding flow; this is the
  // gentler follow-up for users who skipped it.
  Future<void> _evaluateDefaultNudgeEligibility() async {
    final dismissed = await OnboardingStore.isNudgeDismissed();
    final isDefault = dismissed || await LauncherService.isDefaultLauncher();
    if (!mounted) return;
    _defaultNudgeEligible = !dismissed && !isDefault;
    _refreshDefaultNudge();
  }

  // Shows or removes the nudge overlay based on the cached eligibility and the
  // current home surface state — hidden whenever the drawer, edit mode, or a
  // pushed route covers the launcher so it never floats over them.
  void _refreshDefaultNudge() {
    if (!mounted) return;
    final covered = _drawerOpen || _editMode || _routeCovered.value;
    final shouldShow = (_defaultNudgeEligible || _seedTimedOut) && !covered;
    if (shouldShow) {
      if (_defaultNudge == null) {
        final overlay = Overlay.of(context);
        _defaultNudge = OverlayEntry(builder: (_) => _buildTopBanners());
        overlay.insert(_defaultNudge!);
      } else {
        // Composition may have changed (nudge dismissed, restore appeared, …).
        _defaultNudge!.markNeedsBuild();
      }
    } else if (_defaultNudge != null) {
      _defaultNudge!.remove();
      _defaultNudge = null;
    }
  }

  // The stacked top banners: the set-as-default nudge and, when the first-run
  // seed timed out, the "Restore home screen layout" action directly beneath
  // it. Both live in the root overlay as thin top bands that never cover the
  // workspace (so first-swipe-to-open-drawer keeps working).
  Widget _buildTopBanners() {
    final topInset = MediaQuery.of(context).padding.top;
    final covered = _drawerOpen || _editMode || _routeCovered.value;
    final showNudge = _defaultNudgeEligible && !covered;
    final showRestore = _seedTimedOut && !covered;
    return Positioned(
      top: topInset + 8,
      left: 16,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showNudge)
            DefaultLauncherNudge(
              onTap: () => LauncherService.requestHomeRole(),
              onDismiss: () {
                OnboardingStore.dismissNudge();
                _defaultNudgeEligible = false;
                _refreshDefaultNudge();
              },
            ),
          if (showNudge && showRestore) const SizedBox(height: 8),
          if (showRestore)
            RestoreLayoutBanner(
              onRestore: _restoreDefaultLayout,
              onDismiss: () {
                setState(() => _seedTimedOut = false);
                _refreshDefaultNudge();
              },
            ),
        ],
      ),
    );
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
      _maybeRevealHome();
      return;
    }
    if (!workspace.wasFreshInstall) {
      _defaultSeedResolved = true;
      await prefs.setBool(_seededFlagKey, true);
      _maybeRevealHome();
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
    _maybeRevealHome();
  }

  // ─── First-run "Setting up your launcher" cover ──────────────────────────

  // Reveals the home the instant the layout is ready: apps loaded AND the
  // default-layout seed resolved. Called after every seed attempt and from the
  // apps/workspace listeners, so the cover lifts as soon as setup completes.
  void _maybeRevealHome() {
    if (!_initializing) return;
    final apps = context.read<AppsCubit>().state;
    final appsReady = apps.apps.isNotEmpty && !apps.loading;
    if (appsReady && _defaultSeedResolved) {
      _finishInitializing(timedOut: false);
    }
  }

  // Hard failsafe: if seeding hasn't resolved after [_initFailsafe], drop the
  // cover and show home anyway. If the layout never got seeded, surface the
  // "Restore home screen layout" action so the user can rebuild it by hand.
  void _onInitTimeout() {
    if (!_initializing) return;
    _finishInitializing(timedOut: true);
  }

  void _finishInitializing({required bool timedOut}) {
    _initFailsafeTimer?.cancel();
    _initFailsafeTimer = null;
    if (!mounted) return;
    setState(() {
      _initializing = false;
      // Only offer "restore" if the timeout fired before the seed resolved.
      _seedTimedOut = timedOut && !_defaultSeedResolved;
    });
    if (_seedTimedOut) _refreshDefaultNudge();
  }

  // Manual re-seed from the "Restore home screen layout" banner (only ever
  // shown after the failsafe timed out without a seeded layout).
  void _restoreDefaultLayout() {
    final apps = context.read<AppsCubit>().state.apps;
    if (apps.isEmpty) return;
    DefaultLayoutSeeder.seed(
      apps: apps,
      workspace: context.read<WorkspaceCubit>(),
      settings: context.read<SettingsCubit>(),
    );
    _defaultSeedResolved = true;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_seededFlagKey, true));
    setState(() => _seedTimedOut = false);
    _refreshDefaultNudge();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Home screen layout restored')),
    );
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
      case 'settings':
        _openAfterCallSettings();
    }
  }

  Future<void> _consumeFeatureRoute() async {
    final featureId = await LauncherService.consumePendingFeatureId();
    if (!mounted || featureId == null || featureId.isEmpty) return;
    if (featureId == 'morning_dashboard') {
      _openGoodMorning();
      return;
    }
    FeatureLaunchDispatcher.openFeature(context, featureId);
  }

  void _openGoodMorning() {
    _prepareHomeForSmartSearch();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<AppsCubit>()),
            BlocProvider.value(value: context.read<SettingsCubit>()),
            BlocProvider.value(
                value: context.read<LauncherFeatureSettingsCubit>()),
          ],
          child: const GoodMorningScreen(),
        ),
      ),
    );
  }

  void _openAfterCallSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<SettingsCubit>()),
            BlocProvider.value(
                value: context.read<LauncherFeatureSettingsCubit>()),
          ],
          child: const SettingsAppearance(child: AfterCallSettingsScreen()),
        ),
      ),
    );
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

  // The richer Smart-search screen opened by the permanent home pill: app
  // search + suggested/frequent apps + recent searches + settings shortcuts +
  // a web fallback.
  void _openSmartSearch({bool pinToHome = true}) {
    if (!mounted) return;
    if (pinToHome) {
      _prepareHomeForSmartSearch();
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    final settings = context.read<SettingsCubit>().state;
    Navigator.push(
      context,
      PageRouteBuilder(
        // Opaque so it covers the home icons and only the wallpaper shows
        // behind the transparent scaffold — the same look as Settings.
        opaque: true,
        // Swap instantly both ways. The default 300ms duration (with no
        // transitionsBuilder) leaves the home route painting underneath this
        // transparent scaffold for the whole window, so the home icons ghost
        // behind the search field and then pop out the moment the animation
        // ends — and again in reverse on the way back. Zero-duration removes
        // that double-paint window entirely, so the overlay just appears.
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<SearchCubit>()),
            BlocProvider.value(
                value: context.read<LauncherFeatureSettingsCubit>()),
            BlocProvider.value(value: context.read<AppsCubit>()),
            BlocProvider.value(value: context.read<SettingsCubit>()),
          ],
          child: SmartSearchScreen(iconShape: settings.iconShape),
        ),
      ),
    );
  }

  void _prepareHomeForSmartSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    _syncCurrentPageToVisibleWorkspacePage();

    final workspace = context.read<WorkspaceCubit>().state;
    if (workspace.pages.isEmpty || _pageController?.hasClients != true) {
      return;
    }

    final homePage =
        workspace.currentPage.clamp(0, workspace.pages.length - 1).toInt();
    final target = _toControllerPage(homePage);
    final rawPage =
        _pageController!.page ?? _pageController!.initialPage.toDouble();
    if ((rawPage - target).abs() < 0.001) return;

    _pageController!.jumpToPage(target);
    _chromeOpacity.value = 1.0;
    _chromeSlide.value = 0.0;
    _activeSection.value = HomeSection.home;
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
          child: const SettingsAppearance(child: LauncherThemesScreen()),
        ),
      ),
    );
  }

  void _openWallpaper() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<SettingsCubit>()),
          ],
          child: const SettingsAppearance(child: WallpaperScreen()),
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
          child: SettingsAppearance(
            child: WidgetPickerScreen(onWidgetAdded: _addWidgetToHomeScreen),
          ),
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

  void _showAppInfoTooltip(AppInfo app, Offset iconCenter,
      {int? page, int? slot}) {
    _dismissAppInfoTooltip();
    final overlay = Overlay.of(context);

    final isFeature = app.isInternalFeature;
    final locked = !isFeature && _isAppLocked(app);

    final actions = <AppMenuAction>[
      AppMenuAction(
        icon: Icons.info_outline,
        label: 'App info',
        onTap: () {
          _dismissAppInfoTooltip();
          final featureId = LauncherFeatureCatalog.idForApp(app);
          if (featureId != null) {
            FeatureLaunchDispatcher.openFeature(context, featureId);
          } else {
            LauncherService.openAppSettings(app.packageName);
          }
        },
      ),
      AppMenuAction(
        icon: Icons.visibility_off_outlined,
        label: 'Hide app',
        onTap: () {
          _dismissAppInfoTooltip();
          _hideApp(app);
        },
      ),
      if (!isFeature)
        AppMenuAction(
          icon: locked ? Icons.lock_open_outlined : Icons.lock_outline,
          label: locked ? 'Unlock app' : 'Lock app',
          onTap: () {
            _dismissAppInfoTooltip();
            context
                .read<LauncherFeatureSettingsCubit>()
                .setAppLocked(app.packageName, !locked);
          },
        ),
      AppMenuAction(
        icon: Icons.remove_circle_outline,
        label: 'Remove from home',
        onTap: () {
          _dismissAppInfoTooltip();
          _removeFromHome(app, page, slot);
        },
      ),
      if (!isFeature)
        AppMenuAction(
          icon: Icons.delete_outline,
          label: 'Uninstall',
          destructive: true,
          onTap: () {
            _dismissAppInfoTooltip();
            LauncherService.uninstallApp(app.packageName);
          },
        ),
    ];

    _appInfoTooltip = OverlayEntry(
      builder: (_) => _AppInfoTooltip(
        app: app,
        iconCenter: iconCenter,
        actions: actions,
        onDismiss: _dismissAppInfoTooltip,
      ),
    );
    overlay.insert(_appInfoTooltip!);
  }

  bool _isAppLocked(AppInfo app) => context
      .read<LauncherFeatureSettingsCubit>()
      .state
      .lockedApps
      .contains(app.packageName);

  void _hideApp(AppInfo app) {
    final settings = context.read<SettingsCubit>().state;
    final hidden = settings.hiddenApps.toSet()..add(app.launcherKey);
    context
        .read<SettingsCubit>()
        .update(settings.copyWith(hiddenApps: hidden.toList()..sort()));
  }

  void _removeFromHome(AppInfo app, int? page, int? slot) {
    // Workspace icons carry their page+slot, so remove them directly.
    if (page != null && slot != null) {
      context.read<WorkspaceCubit>().removeItem(page, slot);
      return;
    }
    // Dock icons have no slot — drop the matching ref from the persisted dock
    // list. Blank the entry (rather than shift) so other dock icons keep their
    // positions, matching how _resolveDockRefs treats empty strings.
    final settings = context.read<SettingsCubit>().state;
    final appsState = context.read<AppsCubit>().state;
    final keys = <String>{
      app.launcherKey,
      app.packageName,
      app.appComponentName,
    };
    final refs = settings.dockPackages.isNotEmpty
        ? List<String>.from(settings.dockPackages)
        : _resolveDockRefs(appsState, settings);
    final idx = refs.indexWhere(keys.contains);
    if (idx < 0) return;
    refs[idx] = '';
    context.read<SettingsCubit>().update(settings.copyWith(dockPackages: refs));
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
            _scheduleMeasureBottomChrome();
            return Scaffold(
              backgroundColor: Colors.transparent,
              extendBody: true,
              // The launcher never hosts a text field, so it should never reflow
              // for the soft keyboard. Without this, popping back from Smart
              // search while its keyboard is mid-dismiss makes the home body
              // resize as the inset shrinks — read as a jarring transition.
              resizeToAvoidBottomInset: false,
              body: Stack(
                children: [
                  if (settings.homeMode == HomeMode.smart) ...[
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
                          activeSection: _activeSection,
                          onDoubleTap: () =>
                              _handleGesture(settings.doubleTapAction),
                          onSwipeUp: () =>
                              _handleGesture(settings.swipeUpAction),
                          onSwipeDown: () =>
                              _handleGesture(settings.swipeDownAction),
                          onLongPress: _enterEditMode,
                          child: Visibility(
                            visible: (!_drawerOpen || _drawerDraggingToHome) &&
                                !_editMode,
                            maintainState: true,
                            maintainAnimation: true,
                            maintainSize: true,
                            child: WorkspaceView(
                              dragController: _dragController,
                              settings: settings,
                              onAppTap: (app) =>
                                  FeatureLaunchDispatcher.launch(context, app),
                              onAppLongPress: (app, page, slot, center) =>
                                  _showAppInfoTooltip(app, center,
                                      page: page, slot: slot),
                              onBackgroundLongPress: _enterEditMode,
                              onPickWidgetForStack: _openWidgetPickerForStack,
                              onPageChanged: (offset) {
                                const MethodChannel(
                                        'com.genrevibes.smartlauncher/wallpaper')
                                    .invokeMethod('setWallpaperOffset',
                                        {'xOffset': offset});
                              },
                              onControllerReady: (ctrl) =>
                                  setState(() => _pageController = ctrl),
                              homeTopInset:
                                  MediaQuery.of(context).padding.top + 8,
                              homeBottomInset: _bottomChromeHeight,
                              discoverBuilder: settings.discoverPageEnabled
                                  ? (ctx) => DiscoverPage(
                                        onOpenSearch: () =>
                                            _openSmartSearch(pinToHome: false),
                                        onLaunchApp: (app) =>
                                            FeatureLaunchDispatcher.launch(
                                                ctx, app),
                                        activeSection: _activeSection,
                                      )
                                  : null,
                              libraryBuilder: settings.appLibraryPageEnabled
                                  ? (ctx) => AppLibraryPage(
                                        onLaunchApp: (app) =>
                                            FeatureLaunchDispatcher.launch(
                                                ctx, app),
                                      )
                                  : null,
                              onSectionSettled: (s) => _activeSection.value = s,
                              onChromeProgress: (v) => _chromeOpacity.value = v,
                              onChromeSlide: (v) => _chromeSlide.value = v,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildBottomChrome(context, settings),
                    ),
                  ] else if (settings.homeMode == HomeMode.ios)
                    IosHomeView(
                      settings: settings,
                      onLaunchApp: (app) =>
                          FeatureLaunchDispatcher.launch(context, app),
                      onOpenSearch: () => _openSmartSearch(pinToHome: true),
                      onOpenWallpaper: _openWallpaper,
                      onOpenSettings: _openSettings,
                    )
                  else
                    MinimalHomeView(
                      settings: settings,
                      onLaunchApp: (app) =>
                          FeatureLaunchDispatcher.launch(context, app),
                      onOpenSearch: () => _openSmartSearch(pinToHome: true),
                      onOpenSettings: _openSettings,
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
                  if (_editMode && settings.homeMode == HomeMode.smart)
                    EditModeOverlay(
                      settings: settings,
                      onDismiss: _exitEditMode,
                      onWallpaper: () {
                        _exitEditMode();
                        _openWallpaper();
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
                        _pageController?.jumpToPage(_toControllerPage(page));
                      },
                    ),
                  // First-run setup cover: top-most so it hides the home while
                  // the default layout seeds. Driven by local state (lifted the
                  // instant the seed resolves, or by the 10s failsafe), so it
                  // only ever appears on the post-onboarding first run.
                  if (_initializing) const LauncherInitializingView(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // Number of flanking pages before home page 0 in the pager. The Discover page
  // (when enabled) occupies pager index 0, so every home-index jump must offset
  // by this. Mirrors WorkspaceView._leadingCount.
  int _leadingCount() =>
      context.read<SettingsCubit>().state.discoverPageEnabled ? 1 : 0;

  // Converts a 0-based home page index into a pager (controller) index.
  int _toControllerPage(int homeIndex) => _leadingCount() + homeIndex;

  // Measures the bottom chrome band (dock + pill + safe area) and feeds it back
  // as WorkspaceView.homeBottomInset so home pages reserve exactly its height.
  void _scheduleMeasureBottomChrome() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box =
          _bottomChromeKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final h = box.size.height;
      if ((h - _bottomChromeHeight).abs() > 0.5) {
        setState(() => _bottomChromeHeight = h);
      }
    });
  }

  // Bottom overlay: the dock and the permanent Smart-search pill. Always mounted
  // (so its height stays measurable) but faded out and non-interactive on the
  // flanking special pages, in edit mode, and while the drawer is open.
  Widget _buildBottomChrome(BuildContext context, LauncherSettings settings) {
    final width = MediaQuery.of(context).size.width;
    return ValueListenableBuilder<double>(
      valueListenable: _chromeSlide,
      builder: (context, slide, child) => Transform.translate(
        offset: Offset(slide * width, 0),
        child: child,
      ),
      child: ValueListenableBuilder<double>(
        valueListenable: _chromeOpacity,
        builder: (context, opacity, child) {
          final hidden = _editMode || (_drawerOpen && !_drawerDraggingToHome);
          final effective = hidden ? 0.0 : opacity;
          return IgnorePointer(
            ignoring: effective < 0.5,
            child: Opacity(opacity: effective, child: child),
          );
        },
        child: Container(
          key: _bottomChromeKey,
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (settings.showDock) _buildDock(context, settings),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: SmartSearchPill(
                  onTap: () => _openSmartSearch(pinToHome: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDock(BuildContext context, LauncherSettings settings) {
    return ValueListenableBuilder<(int, int)?>(
      valueListenable: HomeWidgetStackView.suppressedAt,
      builder: (context, suppressedStack, child) {
        return Visibility(
          visible: suppressedStack == null,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: child!,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        // Outer selector watches only the apps list (not loading / badge
        // fields) so badge pushes and loading toggles don't rebuild the dock.
        child: BlocSelector<AppsCubit, AppsState, List<AppInfo>>(
          selector: (s) => s.apps,
          builder: (context, _) {
            final appsState = context.read<AppsCubit>().state;
            return BlocSelector<WorkspaceCubit, WorkspaceState,
                Map<String, FolderInfo>>(
              selector: (s) => s.folders,
              builder: (context, _) {
                final workspaceState = context.read<WorkspaceCubit>().state;
                return HotseatView(
                  apps: _resolveDockItems(appsState, workspaceState, settings),
                  settings: settings,
                  dragController: _dragController,
                  onSwipeUp: () => _handleGesture(settings.swipeUpAction),
                  onAppTap: (app) =>
                      FeatureLaunchDispatcher.launch(context, app),
                  onAppLongPress: (app, center) =>
                      _showAppInfoTooltip(app, center),
                );
              },
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
      final app = appsState.resolveRef(ref);
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
    return resolved.map((a) => a.launcherKey).toList();
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
    final app = appsState.resolveRef(ref);
    return WorkspaceItemInfo(
      id: app?.id ?? ref.hashCode,
      itemType: ItemType.application,
      packageName: app?.packageName ?? ref,
      componentName: app?.appComponentName ?? ref,
      title: app?.name ?? ref,
      icon: app?.icon,
      iconPath: app?.iconPath,
      launcherFeatureId: app?.launcherFeatureId ??
          LauncherFeatureCatalog.idForComponent(ref) ??
          LauncherFeatureCatalog.idForPackage(ref),
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
            .where((app) =>
                !hidden.contains(app.launcherKey) &&
                !hidden.contains(app.packageName))
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
    final resolved = folder.contents.map((item) {
      final live = appsState.resolveItem(item);
      if (live == null) return item;
      // Internal features must follow the live alias (App Hider disguise);
      // normal apps keep their pinned component/title.
      final isFeature = item.launcherFeatureId != null;
      return WorkspaceItemInfo(
        id: item.id,
        itemType: item.itemType,
        packageName: item.packageName,
        componentName: isFeature
            ? live.appComponentName
            : (item.componentName ?? live.appComponentName),
        title: isFeature ? live.name : (item.title ?? live.name),
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

// ─── App long-press menu (dismisses on tap-away or drag) ─────────────────────

class _AppInfoTooltip extends StatelessWidget {
  final AppInfo app;
  final Offset iconCenter;
  final List<AppMenuAction> actions;
  final VoidCallback onDismiss;

  const _AppInfoTooltip({
    required this.app,
    required this.iconCenter,
    required this.actions,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const menuW = 224.0;
    const gap = 12.0;
    // Title block + divider + one row per action (see AppContextMenu layout).
    final menuH = 60.0 + actions.length * 44.0;

    final left =
        (iconCenter.dx - menuW / 2).clamp(8.0, screenSize.width - menuW - 8);
    // Prefer placing the menu above the icon; fall back below when it would run
    // off the top of the screen.
    final aboveTop = iconCenter.dy - menuH - gap;
    final top = (aboveTop >= 8.0 ? aboveTop : iconCenter.dy + gap)
        .clamp(8.0, screenSize.height - menuH - 8);

    return Stack(
      children: [
        // Full-screen barrier: a tap, or the start of any drag/swipe, dismisses
        // the menu. Opaque so the press never falls through to the workspace
        // underneath (which would launch an app or start a page swipe).
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            onPanStart: (_) => onDismiss(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: AppContextMenu(title: app.name, actions: actions),
        ),
      ],
    );
  }
}
