import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/app_info.dart';
import '../../models/launcher_feature.dart';
import '../../models/launcher_settings.dart';
import '../../services/launcher_service.dart';
import '../../state/apps_cubit.dart';
import '../../state/launcher_feature_cubit.dart';
import '../../state/settings_cubit.dart';
import '../../widgets/icons/feature_icon.dart';
import '../../widgets/icons/shaped_icon.dart';
import '../../widgets/wallpaper/themed_wallpaper_background.dart';
import '../app_library_page.dart';
import '../discover_page.dart';

class IosHomeView extends StatefulWidget {
  final LauncherSettings settings;
  final ValueChanged<AppInfo> onLaunchApp;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenWallpaper;
  final VoidCallback onOpenSettings;

  const IosHomeView({
    super.key,
    required this.settings,
    required this.onLaunchApp,
    required this.onOpenSearch,
    required this.onOpenWallpaper,
    required this.onOpenSettings,
  });

  @override
  State<IosHomeView> createState() => _IosHomeViewState();
}

class _IosHomeViewState extends State<IosHomeView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _jiggle;
  // Page 0 is the Discover special page, so home page 0 lives at controller
  // index 1 and the launcher opens there.
  final _pageController = PageController(initialPage: 1);
  int _currentPage = 1;
  // The page a user drag began from. The snap physics measures commit distance
  // relative to this so the threshold is symmetric forward and backward.
  double _dragOrigin = 1;
  bool _editMode = false;
  bool _searchOpen = false;
  // Controller index of the App Library (far-right) page. Cached during build so
  // the full-screen swipe-up zone (below the pager) can jump straight to it.
  int _libraryPageIndex = 1;

  // Bundled default iOS wallpaper. Used only when the user hasn't set a custom/
  // device wallpaper; if the asset is missing the background falls back to the
  // iOS-style gradient (see ThemedWallpaperBackground).
  static const _iosWallpaperAsset = 'assets/ios_theme/wallpaper/ios_default.jpg';

  @override
  void initState() {
    super.initState();
    _jiggle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
  }

  @override
  void dispose() {
    _jiggle.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return Stack(
      fit: StackFit.expand,
      children: [
        ThemedWallpaperBackground(
          path: settings.customWallpaperPath,
          assetFallback: _iosWallpaperAsset,
          fallbackColors: const [Color(0xFF1A2440), Color(0xFF9C6F72)],
        ),
        BlocBuilder<AppsCubit, AppsState>(
          buildWhen: (prev, next) => prev.apps != next.apps,
          builder: (context, appsState) {
            final apps = _visibleApps(appsState.apps, settings);
            final homePages = _pages(apps, settings);
            final dock = _dockApps(apps, settings);
            // Effective pager layout: [Discover] [home 0..N] [App Library].
            final itemCount = homePages.length + 2;
            _libraryPageIndex = itemCount - 1;
            final homeIndex =
                (_currentPage - 1).clamp(0, homePages.length - 1);
            final onHomePage =
                _currentPage >= 1 && _currentPage <= homePages.length;
            // Space the home grids leave at the bottom for the dock+dots
            // overlay so icons don't slide underneath it.
            final dockReserve = 120.0 + MediaQuery.of(context).padding.bottom;
            // Long-press (home options) and tap (exit edit) live on an opaque
            // wrapper. Neither competes with the PageView's horizontal drag,
            // so paging stays crisp.
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: _showHomeOptions,
              onTap: _editMode ? _exitEditMode : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Full-screen pager so special pages (App Library) can paint a
                  // full-bleed background under the status bar and home area.
                  NotificationListener<ScrollStartNotification>(
                    // Record which page a drag starts from so the physics can
                    // measure commit distance symmetrically (forward and
                    // backward) instead of relative to floor(page).
                    onNotification: (n) {
                      if (n.dragDetails != null) {
                        _dragOrigin = (_pageController.page ?? _dragOrigin)
                            .roundToDouble();
                      }
                      return false;
                    },
                    child: PageView.builder(
                      controller: _pageController,
                      // Custom snapping (pageSnapping:false) so our physics fully
                      // owns the commit threshold; otherwise Flutter's built-in
                      // PageScrollPhysics runs first and a swipe that doesn't
                      // cross ~50% springs back to the page.
                      pageSnapping: false,
                      physics: _editMode
                          ? const NeverScrollableScrollPhysics()
                          : _SnappyPagePhysics(
                              parent: const BouncingScrollPhysics(),
                              origin: () => _dragOrigin,
                            ),
                      itemCount: itemCount,
                      onPageChanged: (value) =>
                          setState(() => _currentPage = value),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return DiscoverPage(
                            onOpenSearch: widget.onOpenSearch,
                            onLaunchApp: widget.onLaunchApp,
                          );
                        }
                        if (index == itemCount - 1) {
                          return _buildLibraryPage(settings);
                        }
                        final page = homePages[index - 1];
                        return SafeArea(
                          bottom: false,
                          child: Padding(
                            padding:
                                EdgeInsets.only(top: 8, bottom: dockReserve),
                            child: _IosPageView(
                              page: page,
                              settings: settings,
                              editMode: _editMode,
                              jiggle: _jiggle,
                              onLaunch: widget.onLaunchApp,
                              onLaunchTemplate: _launchTemplateApp,
                              onLongPress: _showAppMenuAt,
                              onRemove: _hideApp,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Dock + page dots: a bottom overlay shown only on home pages
                  // (never on Discover or the full-bleed App Library).
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      ignoring: !onHomePage,
                      child: AnimatedOpacity(
                        opacity: onHomePage ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: SafeArea(
                          top: false,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PageDots(
                                count: homePages.length,
                                current: homeIndex,
                              ),
                              const SizedBox(height: 8),
                              _Dock(
                                apps: dock,
                                settings: settings,
                                editMode: _editMode,
                                jiggle: _jiggle,
                                onLaunch: widget.onLaunchApp,
                                onLongPress: _showAppMenuAt,
                                onRemove: _removeFromDock,
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        // Full-screen vertical-swipe zone over the home area: swipe down →
        // Spotlight search, swipe up → App Library (the far-right page). It's
        // translucent and only claims vertical drags, so taps, long-press and
        // the PageView's horizontal paging all still reach the content below.
        if (!_editMode)
          Positioned.fill(
            // Active only on a home page. On Discover / App Library it ignores
            // pointers so those pages' own vertical scrolling works; home page
            // grids don't scroll (NeverScrollableScrollPhysics), so there's no
            // gesture to steal there.
            child: IgnorePointer(
              ignoring: !(_currentPage >= 1 && _currentPage < _libraryPageIndex),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity > 320) {
                    setState(() => _searchOpen = true); // pull down → Spotlight
                  } else if (velocity < -320) {
                    _pageController.animateToPage(
                      _libraryPageIndex, // swipe up → App Library
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
              ),
            ),
          ),
        if (_editMode)
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: _exitEditMode,
                  child: const Text('Done'),
                ),
              ),
            ),
          ),
        if (_searchOpen)
          _IosSpotlight(
            settings: settings,
            onClose: () => setState(() => _searchOpen = false),
            onLaunch: widget.onLaunchApp,
          ),
      ],
    );
  }

  /// The far-right App Library page, rendered full-bleed (under the status bar
  /// and home area). Its blurred wallpaper and dim scrim live INSIDE the page —
  /// not as a BackdropFilter over the pager — so the blur can't bleed onto the
  /// neighbouring home page while swiping between them.
  Widget _buildLibraryPage(LauncherSettings settings) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ThemedWallpaperBackground(
          path: settings.customWallpaperPath,
          assetFallback: _iosWallpaperAsset,
          fallbackColors: const [Color(0xFF1A2440), Color(0xFF9C6F72)],
          blur: true,
          blurSigma: 28,
        ),
        const ColoredBox(color: Color(0x99000000)),
        AppLibraryPage(
          onLaunchApp: widget.onLaunchApp,
          translucent: true,
        ),
      ],
    );
  }

  List<AppInfo> _visibleApps(List<AppInfo> apps, LauncherSettings settings) {
    final hidden = settings.hiddenApps.toSet();
    return apps
        .where((app) =>
            !hidden.contains(app.launcherKey) &&
            !hidden.contains(app.packageName))
        .toList();
  }

  /// The launcher's own mini-apps (Clock, App Locker, App Hider, File Locker),
  /// resolved to the live [AppInfo] from the apps list when available (so their
  /// icons render) and falling back to the catalog entry otherwise.
  List<AppInfo> _miniApps(List<AppInfo> apps) {
    final byFeatureId = {
      for (final app in apps)
        if (app.launcherFeatureId != null) app.launcherFeatureId!: app,
    };
    return LauncherFeatureCatalog.homeFeatures
        .map((feature) => byFeatureId[feature.id] ?? feature.toAppInfo())
        .toList(growable: false);
  }

  List<_IosPage> _pages(List<AppInfo> apps, LauncherSettings settings) {
    final miniApps = _miniApps(apps);
    final template = _resolveTemplateApps(apps);
    final templatePackages = template
        .expand((icon) => [
              icon.primaryPackage,
              ...icon.fallbackPackages,
              icon.app?.packageName,
            ])
        .whereType<String>()
        .toSet();
    final remaining = apps
        .where((app) =>
            !app.isInternalFeature &&
            !templatePackages.contains(app.packageName))
        .toList();
    final columns = settings.iosGridColumns.clamp(3, 5).toInt();
    final size = columns * 5;
    // The first page also shows the widgets row and a mini-apps row, so it
    // holds fewer template icons (two rows) to keep it from feeling cramped.
    // The rest flow onto subsequent full-height pages.
    final firstPageCount = columns * 2;
    final pages = <_IosPage>[
      _IosPage(
        miniApps: miniApps,
        templateApps: template.take(firstPageCount).toList(),
        showWidgets: true,
      ),
    ];
    for (var i = firstPageCount; i < template.length; i += size) {
      pages.add(
        _IosPage(
          templateApps:
              template.sublist(i, math.min(template.length, i + size)),
        ),
      );
    }
    for (var i = 0; i < remaining.length; i += size) {
      pages.add(
        _IosPage(
          apps: remaining.sublist(i, math.min(remaining.length, i + size)),
        ),
      );
    }
    return pages;
  }

  List<AppInfo> _dockApps(List<AppInfo> apps, LauncherSettings settings) {
    final refs = settings.dockPackages.isNotEmpty
        ? settings.dockPackages
        : settings.iosDockPackages.isNotEmpty
            ? settings.iosDockPackages
            : const [
                'com.android.dialer',
                'com.android.contacts',
                'com.android.messaging',
                'com.android.chrome',
                'com.android.camera2',
              ];
    final byKey = {for (final app in apps) app.launcherKey: app};
    final byPackage = {for (final app in apps) app.packageName: app};
    final resolved = <AppInfo>[];
    for (final ref in refs) {
      final app = byKey[ref] ?? byPackage[ref];
      if (app != null && !resolved.contains(app)) resolved.add(app);
      if (resolved.length == 4) break;
    }
    if (resolved.isEmpty) resolved.addAll(apps.take(4));
    return resolved;
  }

  List<_IosTemplateApp> _resolveTemplateApps(List<AppInfo> apps) {
    return _iosTemplateApps.map((template) {
      final app = _findPackage(
        apps,
        [template.primaryPackage, ...template.fallbackPackages],
      );
      return template.copyWith(app: app);
    }).toList(growable: false);
  }

  AppInfo? _findPackage(List<AppInfo> apps, List<String> packages) {
    for (final package in packages) {
      for (final app in apps) {
        if (app.packageName == package) return app;
      }
    }
    return null;
  }

  Future<void> _launchTemplateApp(_IosTemplateApp template) async {
    final app = template.app;
    if (app != null) {
      widget.onLaunchApp(app);
      return;
    }
    for (final package in [
      template.primaryPackage,
      ...template.fallbackPackages,
    ]) {
      if (await LauncherService.launchApp(package)) return;
    }
  }

  void _enterEditMode() {
    if (_editMode) return;
    setState(() => _editMode = true);
    _jiggle.repeat(reverse: true);
  }

  void _exitEditMode() {
    _jiggle.stop();
    _jiggle.value = 0;
    setState(() => _editMode = false);
  }

  void _hideApp(AppInfo app) {
    final settings = context.read<SettingsCubit>().state;
    final hidden = settings.hiddenApps.toSet()..add(app.launcherKey);
    context.read<SettingsCubit>().update(
          settings.copyWith(hiddenApps: hidden.toList()..sort()),
        );
  }

  void _removeFromDock(AppInfo app) {
    final settings = context.read<SettingsCubit>().state;
    final refs = settings.iosDockPackages
        .where((ref) => ref != app.launcherKey && ref != app.packageName)
        .toList();
    context.read<SettingsCubit>().update(
          settings.copyWith(iosDockPackages: refs),
        );
  }

  void _addToDock(AppInfo app) {
    final settings = context.read<SettingsCubit>().state;
    final refs = settings.iosDockPackages.isEmpty
        ? _dockApps(context.read<AppsCubit>().state.apps, settings)
            .map((a) => a.launcherKey)
            .toList()
        : List<String>.from(settings.iosDockPackages);
    refs.removeWhere((ref) => ref == app.launcherKey || ref == app.packageName);
    refs.add(app.launcherKey);
    context.read<SettingsCubit>().update(
          settings.copyWith(iosDockPackages: refs.take(4).toList()),
        );
  }

  void _showHomeOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _HomeOptionsSheet(
        onChangeWallpaper: () {
          Navigator.pop(context);
          widget.onOpenWallpaper();
        },
        onEditHome: () {
          Navigator.pop(context);
          _enterEditMode();
        },
        onSettings: () {
          Navigator.pop(context);
          widget.onOpenSettings();
        },
      ),
    );
  }

  Future<void> _showAppMenuAt(AppInfo app, Offset globalPosition) async {
    final settings = context.read<SettingsCubit>().state;
    final dock = _dockApps(context.read<AppsCubit>().state.apps, settings);
    final inDock =
        dock.any((dockApp) => dockApp.packageName == app.packageName);
    final dockFull = !inDock && dock.length >= settings.dockSize.clamp(0, 5);
    final fallbackPosition = Offset(
      MediaQuery.of(context).size.width / 2,
      MediaQuery.of(context).size.height / 2,
    );
    final featureCubit = context.read<LauncherFeatureSettingsCubit>();
    final isLocked = featureCubit.state.lockedApps.contains(app.packageName);
    final action = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.08),
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (context, _, __) => _IosContextMenuOverlay(
        globalPosition:
            globalPosition == Offset.zero ? fallbackPosition : globalPosition,
        appName: app.name,
        inDock: inDock,
        dockFull: dockFull,
        isLocked: isLocked,
        canLock: !app.isInternalFeature,
      ),
    );
    switch (action) {
      case 'dock_add':
        _addToDock(app);
        break;
      case 'dock_remove':
        _removeFromDock(app);
        break;
      case 'app_info':
        LauncherService.openAppSettings(app.packageName);
        break;
      case 'lock':
        featureCubit.setAppLocked(app.packageName, !isLocked);
        break;
      case 'hide':
      case 'remove':
        _hideApp(app);
        break;
      case 'edit_home':
        _enterEditMode();
        break;
    }
  }
}

class _IosPage {
  final List<AppInfo> apps;
  final List<AppInfo> miniApps;
  final List<_IosTemplateApp> templateApps;
  final bool showWidgets;

  const _IosPage({
    this.apps = const [],
    this.miniApps = const [],
    this.templateApps = const [],
    this.showWidgets = false,
  });
}

class _IosTemplateApp {
  final String name;
  final String assetPath;
  final String primaryPackage;
  final List<String> fallbackPackages;
  final AppInfo? app;

  const _IosTemplateApp(
    this.name,
    this.assetPath,
    this.primaryPackage, [
    this.fallbackPackages = const [],
    this.app,
  ]);

  _IosTemplateApp copyWith({AppInfo? app}) => _IosTemplateApp(
        name,
        assetPath,
        primaryPackage,
        fallbackPackages,
        app,
      );
}

const _iosTemplateApps = <_IosTemplateApp>[
  _IosTemplateApp('Calendar', 'assets/ios_theme/CalendarIcon.png',
      'com.google.android.calendar', [
    'com.android.calendar',
    'com.samsung.android.calendar',
  ]),
  _IosTemplateApp('Photos', 'assets/ios_theme/PhotosIcon.png',
      'com.google.android.apps.photos', [
    'com.sec.android.gallery3d',
    'com.miui.gallery',
    'com.android.gallery3d',
  ]),
  _IosTemplateApp(
      'Maps', 'assets/ios_theme/MapsIcon.png', 'com.google.android.apps.maps', [
    'com.waze',
    'com.here.app.maps',
  ]),
  _IosTemplateApp('Reminders', 'assets/ios_theme/RemindersIcon.png',
      'com.google.android.apps.tasks', [
    'org.tasks',
    'com.android.task',
  ]),
  _IosTemplateApp('Health', 'assets/ios_theme/HealthIcon.png',
      'com.google.android.apps.fitness', [
    'com.samsung.android.app.health',
  ]),
  _IosTemplateApp('Wallet', 'assets/ios_theme/WalletIcon.png',
      'com.google.android.apps.walletnfcrel', [
    'com.samsung.android.spay',
    'com.paypal.android.p2pmobile',
  ]),
  _IosTemplateApp(
      'Settings', 'assets/ios_theme/SettingsIcon.png', 'com.android.settings'),
  _IosTemplateApp('Camera', 'assets/ios_theme/CameraIcon.png',
      'com.google.android.GoogleCamera', [
    'com.android.camera2',
    'com.android.camera',
    'com.samsung.android.app.camera',
  ]),
  _IosTemplateApp('Clock', 'assets/ios_theme/ClockIcon.png',
      'com.google.android.deskclock', [
    'com.android.deskclock',
    'com.samsung.android.app.clockpackage',
  ]),
  _IosTemplateApp(
      'Mail', 'assets/ios_theme/MailIcon.png', 'com.google.android.gm', [
    'com.android.email',
    'com.microsoft.office.outlook',
  ]),
  _IosTemplateApp(
      'Music', 'assets/ios_theme/MusicIcon.png', 'com.spotify.music', [
    'com.google.android.music',
    'com.android.music',
    'com.samsung.android.app.music',
  ]),
  _IosTemplateApp(
      'Notes', 'assets/ios_theme/NotesIcon.png', 'com.google.android.keep', [
    'com.evernote',
    'com.microsoft.office.onenote',
  ]),
  _IosTemplateApp(
      'App Store', 'assets/ios_theme/AppStoreIcon.png', 'com.android.vending'),
  _IosTemplateApp(
      'Safari', 'assets/ios_theme/SafariIcon.png', 'com.android.chrome', [
    'org.mozilla.firefox',
    'com.brave.browser',
    'com.opera.browser',
  ]),
  _IosTemplateApp('Messages', 'assets/ios_theme/MessagesIcon.png',
      'com.google.android.apps.messaging', [
    'com.android.mms',
    'com.samsung.android.messaging',
  ]),
  _IosTemplateApp('FaceTime', 'assets/ios_theme/FacetimeIcon.png',
      'com.google.android.apps.tachyon', [
    'com.google.android.apps.meet',
    'us.zoom.videomeetings',
  ]),
  _IosTemplateApp('Weather', 'assets/ios_theme/WeatherIcon.png',
      'com.google.android.apps.weather', [
    'com.weather.Weather',
  ]),
  _IosTemplateApp('Videos', 'assets/ios_theme/VideosIcon.png',
      'com.google.android.youtube', [
    'com.netflix.mediaclient',
    'com.amazon.avod.thirdpartyclient',
  ]),
  _IosTemplateApp(
      'Books', 'assets/ios_theme/BooksIcon.png', 'com.amazon.kindle', [
    'com.google.android.apps.books',
    'com.kobo.android',
  ]),
  _IosTemplateApp('iTunes Store', 'assets/ios_theme/ItunesIcon.png',
      'com.google.android.apps.youtube.music', [
    'com.amazon.mp3',
    'com.deezer.android.app',
  ]),
];

/// Page physics tuned so a deliberate swipe reliably flips to the next page
/// instead of springing back, while never skipping more than one page at a time.
/// It lowers the drag-distance commit threshold (≈33% of a page vs Flutter's
/// default 50%) and the fling-velocity threshold. It deliberately keeps the
/// default (light, critically-damped) spring — a heavy spring would let a fling
/// carry momentum across several pages.
///
/// Must be paired with `pageSnapping: false` on the PageView so this class — not
/// Flutter's built-in PageScrollPhysics — decides which page to land on. Assumes
/// the default viewportFraction of 1.0 (one page == one viewport width).
class _SnappyPagePhysics extends ScrollPhysics {
  /// Returns the page the current drag started from, so commit distance is
  /// measured symmetrically forward and backward (not relative to floor(page),
  /// which made backward swipes need ~80% travel while forward needed ~20%).
  final double Function()? origin;

  const _SnappyPagePhysics({super.parent, this.origin});

  @override
  _SnappyPagePhysics applyTo(ScrollPhysics? ancestor) =>
      _SnappyPagePhysics(parent: buildParent(ancestor), origin: origin);

  @override
  double get minFlingVelocity => 20.0;

  double _targetPixels(ScrollMetrics position, double velocity) {
    final viewport = position.viewportDimension;
    if (viewport <= 0) return position.pixels;
    final page = position.pixels / viewport;
    final from = (origin?.call() ?? page.roundToDouble());
    // Signed travel from where the drag began: + forward, - backward.
    final delta = page - from;

    // Decide by distance first; velocity only *assists*, it never vetoes a real
    // drag (a firm swipe whose finger decelerates on lift can register a small
    // opposite velocity, which must not throw away the drag). Snap at most one
    // page from the origin so a fast drag never skips pages.
    double target = from;
    if (delta >= 0.6) {
      target = from + 1; // deep forward drag commits regardless of velocity
    } else if (delta <= -0.6) {
      target = from - 1; // deep backward drag commits regardless of velocity
    } else if (velocity > minFlingVelocity) {
      target = from + 1; // forward flick
    } else if (velocity < -minFlingVelocity) {
      target = from - 1; // backward flick
    } else if (delta >= 0.2) {
      target = from + 1; // neutral release, dragged ~1/5 page forward
    } else if (delta <= -0.2) {
      target = from - 1; // neutral release, dragged ~1/5 page backward
    }
    return (target * viewport).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    // Defer to the parent (bouncing) physics at the edges so overscroll glow /
    // rubber-band still works past the first/last page.
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final target = _targetPixels(position, velocity);
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}

class _IosPageView extends StatelessWidget {
  final _IosPage page;
  final LauncherSettings settings;
  final bool editMode;
  final Animation<double> jiggle;
  final ValueChanged<AppInfo> onLaunch;
  final ValueChanged<_IosTemplateApp> onLaunchTemplate;
  final void Function(AppInfo app, Offset globalPosition) onLongPress;
  final ValueChanged<AppInfo> onRemove;

  const _IosPageView({
    required this.page,
    required this.settings,
    required this.editMode,
    required this.jiggle,
    required this.onLaunch,
    required this.onLaunchTemplate,
    required this.onLongPress,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (page.showWidgets && !editMode) const _HomeWidgetsRow(),
        if (page.miniApps.isNotEmpty)
          _IconGrid(
            apps: page.miniApps,
            settings: settings,
            editMode: editMode,
            jiggle: jiggle,
            shrinkWrap: true,
            onLaunch: onLaunch,
            onLongPress: onLongPress,
            onRemove: onRemove,
          ),
        Expanded(
          child: page.templateApps.isNotEmpty
              ? _TemplateIconGrid(
                  icons: page.templateApps,
                  settings: settings,
                  editMode: editMode,
                  jiggle: jiggle,
                  onLaunch: onLaunchTemplate,
                  onLongPress: (template, position) {
                    final app = template.app;
                    if (app != null) onLongPress(app, position);
                  },
                  onRemove: (template) {
                    final app = template.app;
                    if (app != null) onRemove(app);
                  },
                )
              : _IconGrid(
                  apps: page.apps,
                  settings: settings,
                  editMode: editMode,
                  jiggle: jiggle,
                  onLaunch: onLaunch,
                  onLongPress: onLongPress,
                  onRemove: onRemove,
                ),
        ),
      ],
    );
  }
}

class _IconGrid extends StatelessWidget {
  final List<AppInfo> apps;
  final LauncherSettings settings;
  final bool editMode;
  final Animation<double> jiggle;
  final bool shrinkWrap;
  final ValueChanged<AppInfo> onLaunch;
  final void Function(AppInfo app, Offset globalPosition) onLongPress;
  final ValueChanged<AppInfo> onRemove;

  const _IconGrid({
    required this.apps,
    required this.settings,
    required this.editMode,
    required this.jiggle,
    this.shrinkWrap = false,
    required this.onLaunch,
    required this.onLongPress,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      shrinkWrap: shrinkWrap,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: settings.iosGridColumns.clamp(3, 5).toInt(),
        mainAxisSpacing: 14,
        crossAxisSpacing: 10,
        childAspectRatio: 0.76,
      ),
      itemCount: apps.length,
      itemBuilder: (context, index) => _IosAppTile(
        app: apps[index],
        settings: settings,
        editMode: editMode,
        jiggle: jiggle,
        index: index,
        onTap: () => editMode ? null : onLaunch(apps[index]),
        onLongPress: (position) => onLongPress(apps[index], position),
        onRemove: () => onRemove(apps[index]),
      ),
    );
  }
}

class _TemplateIconGrid extends StatelessWidget {
  final List<_IosTemplateApp> icons;
  final LauncherSettings settings;
  final bool editMode;
  final Animation<double> jiggle;
  final ValueChanged<_IosTemplateApp> onLaunch;
  final void Function(_IosTemplateApp app, Offset globalPosition) onLongPress;
  final ValueChanged<_IosTemplateApp> onRemove;

  const _TemplateIconGrid({
    required this.icons,
    required this.settings,
    required this.editMode,
    required this.jiggle,
    required this.onLaunch,
    required this.onLongPress,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: settings.iosGridColumns.clamp(3, 5).toInt(),
        mainAxisSpacing: 14,
        crossAxisSpacing: 10,
        childAspectRatio: 0.76,
      ),
      itemCount: icons.length,
      itemBuilder: (context, index) => _IosTemplateTile(
        icon: icons[index],
        settings: settings,
        editMode: editMode,
        jiggle: jiggle,
        index: index,
        onTap: () => editMode ? null : onLaunch(icons[index]),
        onLongPress: (position) => onLongPress(icons[index], position),
        onRemove: () => onRemove(icons[index]),
      ),
    );
  }
}

class _IosAppTile extends StatelessWidget {
  final AppInfo app;
  final LauncherSettings settings;
  final bool editMode;
  final Animation<double> jiggle;
  final int index;
  final VoidCallback onTap;
  final ValueChanged<Offset> onLongPress;
  final VoidCallback onRemove;

  const _IosAppTile({
    required this.app,
    required this.settings,
    required this.editMode,
    required this.jiggle,
    required this.index,
    required this.onTap,
    required this.onLongPress,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    Widget child = GestureDetector(
      onTap: onTap,
      onLongPressStart: (details) => onLongPress(details.globalPosition),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Icon(app: app, size: settings.iosGridColumns <= 3 ? 66 : 58),
              const SizedBox(height: 5),
              Text(
                app.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: settings.labelSize.clamp(10, 14),
                  shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
                ),
              ),
            ],
          ),
          if (editMode)
            Positioned(
              top: -7,
              left: 10,
              child: GestureDetector(
                onTap: onRemove,
                child: const CircleAvatar(
                  radius: 11,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.close, size: 16, color: Colors.black87),
                ),
              ),
            ),
        ],
      ),
    );
    if (!editMode) return child;
    return AnimatedBuilder(
      animation: jiggle,
      builder: (context, _) {
        final direction = index.isEven ? 1.0 : -1.0;
        return Transform.rotate(
          angle: direction * (jiggle.value - 0.5) * 0.045,
          child: child,
        );
      },
    );
  }
}

class _IosTemplateTile extends StatelessWidget {
  final _IosTemplateApp icon;
  final LauncherSettings settings;
  final bool editMode;
  final Animation<double> jiggle;
  final int index;
  final VoidCallback onTap;
  final ValueChanged<Offset> onLongPress;
  final VoidCallback onRemove;

  const _IosTemplateTile({
    required this.icon,
    required this.settings,
    required this.editMode,
    required this.jiggle,
    required this.index,
    required this.onTap,
    required this.onLongPress,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    Widget child = GestureDetector(
      onTap: onTap,
      onLongPressStart: (details) => onLongPress(details.globalPosition),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(
                  settings.iosGridColumns <= 3 ? 16 : 14,
                ),
                child: Image.asset(
                  icon.assetPath,
                  width: settings.iosGridColumns <= 3 ? 66 : 58,
                  height: settings.iosGridColumns <= 3 ? 66 : 58,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                icon.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: settings.labelSize.clamp(10, 14),
                  shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
                ),
              ),
            ],
          ),
          if (editMode && icon.app != null)
            Positioned(
              top: -7,
              left: 10,
              child: GestureDetector(
                onTap: onRemove,
                child: const CircleAvatar(
                  radius: 11,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.close, size: 16, color: Colors.black87),
                ),
              ),
            ),
        ],
      ),
    );
    if (!editMode) return child;
    return AnimatedBuilder(
      animation: jiggle,
      builder: (context, _) {
        final direction = index.isEven ? 1.0 : -1.0;
        return Transform.rotate(
          angle: direction * (jiggle.value - 0.5) * 0.045,
          child: child,
        );
      },
    );
  }
}

class _Icon extends StatelessWidget {
  final AppInfo app;
  final double size;

  const _Icon({required this.app, required this.size});

  @override
  Widget build(BuildContext context) {
    if (app.isInternalFeature) {
      return FeatureIcon(
        featureId: app.launcherFeatureId,
        packageName: app.packageName,
        componentName: app.appComponentName,
        size: size,
      );
    }
    return ShapedIcon(
      iconBytes: app.icon,
      iconPath: app.iconPath,
      shape: 'squircle',
      size: size,
      cacheKey: app.packageName,
    );
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int current;

  const _PageDots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: i == current ? 16 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: i == current ? 0.9 : 0.38),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

class _Dock extends StatelessWidget {
  final List<AppInfo> apps;
  final LauncherSettings settings;
  final bool editMode;
  final Animation<double> jiggle;
  final ValueChanged<AppInfo> onLaunch;
  final void Function(AppInfo app, Offset globalPosition) onLongPress;
  final ValueChanged<AppInfo> onRemove;

  const _Dock({
    required this.apps,
    required this.settings,
    required this.editMode,
    required this.jiggle,
    required this.onLaunch,
    required this.onLongPress,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final row = SizedBox(
      height: 88,
      width: MediaQuery.of(context).size.width - 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < apps.length; i++)
            SizedBox(
              width: 72,
              child: _IosAppTile(
                app: apps[i],
                settings: settings,
                editMode: editMode,
                jiggle: jiggle,
                index: i,
                onTap: () => editMode ? null : onLaunch(apps[i]),
                onLongPress: (position) => onLongPress(apps[i], position),
                onRemove: () => onRemove(apps[i]),
              ),
            ),
        ],
      ),
    );
    if (!settings.dockShowBackground) return row;
    // Flat translucent panel instead of a live BackdropFilter blur — the dock
    // is on screen during every page swipe, so its per-frame blur was a
    // constant jank source.
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: settings.dockBackgroundColor.withValues(
            alpha: settings.dockBackgroundOpacity,
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: row,
      ),
    );
  }
}

class _HomeOptionsSheet extends StatelessWidget {
  final VoidCallback onChangeWallpaper;
  final VoidCallback onEditHome;
  final VoidCallback onSettings;

  const _HomeOptionsSheet({
    required this.onChangeWallpaper,
    required this.onEditHome,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.6),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white30,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  _SheetTile(
                    icon: Icons.wallpaper,
                    label: 'Change Wallpaper',
                    onTap: onChangeWallpaper,
                  ),
                  _SheetTile(
                    icon: Icons.grid_view_rounded,
                    label: 'Edit Home Screen',
                    onTap: onEditHome,
                  ),
                  _SheetTile(
                    icon: Icons.settings,
                    label: 'Settings',
                    onTap: onSettings,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SheetTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _IosContextMenuOverlay extends StatelessWidget {
  final Offset globalPosition;
  final String appName;
  final bool inDock;
  final bool dockFull;
  final bool isLocked;
  final bool canLock;

  const _IosContextMenuOverlay({
    required this.globalPosition,
    required this.appName,
    required this.inDock,
    required this.dockFull,
    required this.isLocked,
    required this.canLock,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const menuW = 220.0;
    const itemH = 48.0;
    const arrowH = 10.0;
    // Remove App, Edit Home, Dock toggle, Hide app, App Info (+ Lock if shown).
    final itemCount = canLock ? 6 : 5;
    final menuH = itemH * itemCount + 2;
    var left = globalPosition.dx - menuW / 2;
    left = left.clamp(12.0, size.width - menuW - 12);
    var top = globalPosition.dy - menuH - arrowH - 10;
    var arrowBelow = true;
    if (top < 60) {
      top = globalPosition.dy + 20;
      arrowBelow = false;
    }
    final arrowLeft = (globalPosition.dx - left - 10).clamp(12.0, menuW - 32);
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        // Any swipe/drag anywhere dismisses the menu (it shouldn't linger while
        // the user swipes pages).
        onVerticalDragStart: (_) => Navigator.pop(context),
        onHorizontalDragStart: (_) => Navigator.pop(context),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!arrowBelow)
                      Padding(
                        padding: EdgeInsets.only(left: arrowLeft),
                        child: CustomPaint(
                          size: const Size(20, arrowH),
                          painter: _ArrowPainter(up: true),
                        ),
                      ),
                    _MenuCard(
                      inDock: inDock,
                      dockFull: dockFull,
                      isLocked: isLocked,
                      canLock: canLock,
                    ),
                    if (arrowBelow)
                      Padding(
                        padding: EdgeInsets.only(left: arrowLeft),
                        child: CustomPaint(
                          size: const Size(20, arrowH),
                          painter: _ArrowPainter(up: false),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final bool up;

  const _ArrowPainter({required this.up});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (up) {
      path
        ..moveTo(0, size.height)
        ..lineTo(size.width / 2, 0)
        ..lineTo(size.width, size.height);
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MenuCard extends StatelessWidget {
  final bool inDock;
  final bool dockFull;
  final bool isLocked;
  final bool canLock;

  const _MenuCard({
    required this.inDock,
    required this.dockFull,
    required this.isLocked,
    required this.canLock,
  });

  @override
  Widget build(BuildContext context) {
    const divider = Divider(height: 1, thickness: 1, color: Color(0xFFE5E5EA));
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SizedBox(
          width: 220,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ContextMenuItem(
                icon: Icons.remove_circle_outline,
                label: 'Remove App',
                iconColor: Colors.red,
                labelColor: Colors.red,
                onTap: () => Navigator.pop(context, 'remove'),
              ),
              divider,
              _ContextMenuItem(
                icon: Icons.grid_view_rounded,
                label: 'Edit Home Screen',
                onTap: () => Navigator.pop(context, 'edit_home'),
              ),
              divider,
              if (inDock)
                _ContextMenuItem(
                  icon: Icons.remove_from_queue,
                  label: 'Remove from Dock',
                  iconColor: Colors.orange,
                  onTap: () => Navigator.pop(context, 'dock_remove'),
                )
              else
                _ContextMenuItem(
                  icon: Icons.add_to_queue,
                  label: dockFull ? 'Dock is Full' : 'Add to Dock',
                  iconColor: dockFull ? Colors.grey : Colors.blue,
                  labelColor: dockFull ? Colors.grey : null,
                  onTap: dockFull
                      ? null
                      : () => Navigator.pop(context, 'dock_add'),
                ),
              divider,
              if (canLock) ...[
                _ContextMenuItem(
                  icon: isLocked ? Icons.lock_open_outlined : Icons.lock_outline,
                  label: isLocked ? 'Unlock App' : 'Lock App',
                  onTap: () => Navigator.pop(context, 'lock'),
                ),
                divider,
              ],
              _ContextMenuItem(
                icon: Icons.visibility_off_outlined,
                label: 'Hide App',
                onTap: () => Navigator.pop(context, 'hide'),
              ),
              divider,
              _ContextMenuItem(
                icon: Icons.info_outline,
                label: 'App Info',
                onTap: () => Navigator.pop(context, 'app_info'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContextMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  final Color? labelColor;
  final VoidCallback? onTap;

  const _ContextMenuItem({
    required this.icon,
    required this.label,
    this.iconColor,
    this.labelColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: labelColor ?? Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(icon, color: iconColor ?? Colors.black54, size: 20),
          ],
        ),
      ),
    );
  }
}

class _HomeWidgetsRow extends StatelessWidget {
  const _HomeWidgetsRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: SizedBox(
        height: 158,
        child: Row(
          children: [
            Expanded(child: _ClockWidget()),
            SizedBox(width: 12),
            Expanded(child: _CalendarWidget()),
          ],
        ),
      ),
    );
  }
}

class _ClockWidget extends StatefulWidget {
  const _ClockWidget();

  @override
  State<_ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<_ClockWidget> {
  late DateTime _now;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _launchFirstAvailable([
        'com.google.android.deskclock',
        'com.android.deskclock',
        'com.samsung.android.app.clockpackage',
      ]),
      // Flat translucent panel instead of a live BackdropFilter blur — the
      // blur re-sampled the backdrop every frame while the page translated,
      // which made paging janky.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ColoredBox(
          color: Colors.white.withValues(alpha: 0.18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              children: [
                Expanded(
                  child: CustomPaint(
                    painter: _AnalogClockPainter(_now),
                    size: Size.infinite,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Clock',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalogClockPainter extends CustomPainter {
  final DateTime time;

  const _AnalogClockPainter(this.time);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(cx, cy) - 2;
    final center = Offset(cx, cy);
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    final tickPaint = Paint()
      ..color = Colors.black45
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final angle = i * 30 * math.pi / 180 - math.pi / 2;
      final inner = center +
          Offset(
              math.cos(angle) * radius * 0.82, math.sin(angle) * radius * 0.82);
      final outer = center +
          Offset(
              math.cos(angle) * radius * 0.94, math.sin(angle) * radius * 0.94);
      canvas.drawLine(inner, outer, tickPaint);
    }
    _hand(
      canvas,
      center,
      ((time.hour % 12) + time.minute / 60) * 30 * math.pi / 180 - math.pi / 2,
      radius * 0.5,
      4.5,
      Colors.black87,
    );
    _hand(
      canvas,
      center,
      (time.minute + time.second / 60) * 6 * math.pi / 180 - math.pi / 2,
      radius * 0.7,
      3,
      Colors.black87,
    );
    _hand(
      canvas,
      center,
      time.second * 6 * math.pi / 180 - math.pi / 2,
      radius * 0.74,
      1.5,
      const Color(0xFFFF3B30),
    );
    canvas.drawCircle(center, 5, Paint()..color = const Color(0xFFFF3B30));
    canvas.drawCircle(center, 2.5, Paint()..color = Colors.white);
  }

  void _hand(
    Canvas canvas,
    Offset center,
    double angle,
    double length,
    double width,
    Color color,
  ) {
    canvas.drawLine(
      center,
      center + Offset(math.cos(angle) * length, math.sin(angle) * length),
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_AnalogClockPainter oldDelegate) =>
      oldDelegate.time.second != time.second;
}

class _CalendarWidget extends StatefulWidget {
  const _CalendarWidget();

  @override
  State<_CalendarWidget> createState() => _CalendarWidgetState();
}

class _CalendarWidgetState extends State<_CalendarWidget> {
  late DateTime _now;
  late Timer _timer;

  static const _monthNames = [
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];
  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(_now.year, _now.month).weekday;
    final offset = firstWeekday - 1;
    final daysInMonth = DateTime(_now.year, _now.month + 1, 0).day;
    final weeks = ((offset + daysInMonth) / 7).ceil();
    return GestureDetector(
      onTap: () => _launchFirstAvailable([
        'com.google.android.calendar',
        'com.android.calendar',
        'com.samsung.android.calendar',
      ]),
      // Flat translucent panel instead of a live BackdropFilter blur (see
      // _ClockWidget) to keep page swiping smooth.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ColoredBox(
          color: Colors.white.withValues(alpha: 0.18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _monthNames[_now.month - 1],
                    style: const TextStyle(
                      color: Color(0xFFFF9F0A),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: _dayLabels
                        .map(
                          (day) => SizedBox(
                            width: 20,
                            child: Text(
                              day,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(weeks, (week) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(7, (col) {
                            final day = week * 7 + col - offset + 1;
                            if (day < 1 || day > daysInMonth) {
                              return const SizedBox(width: 20, height: 18);
                            }
                            final isToday = day == _now.day;
                            return SizedBox(
                              width: 20,
                              height: 18,
                              child: DecoratedBox(
                                decoration: isToday
                                    ? const BoxDecoration(
                                        color: Color(0xFFFF3B30),
                                        shape: BoxShape.circle,
                                      )
                                    : const BoxDecoration(),
                                child: Center(
                                  child: Text(
                                    '$day',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                          alpha: isToday ? 1 : 0.85),
                                      fontSize: 10,
                                      fontWeight: isToday
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}

Future<void> _launchFirstAvailable(List<String> packages) async {
  for (final package in packages) {
    if (await LauncherService.launchApp(package)) return;
  }
}

class _IosSpotlight extends StatefulWidget {
  final LauncherSettings settings;
  final VoidCallback onClose;
  final ValueChanged<AppInfo> onLaunch;

  const _IosSpotlight({
    required this.settings,
    required this.onClose,
    required this.onLaunch,
  });

  @override
  State<_IosSpotlight> createState() => _IosSpotlightState();
}

class _IosSpotlightState extends State<_IosSpotlight> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final appsState = context.watch<AppsCubit>().state;
    final hidden = widget.settings.hiddenApps.toSet();
    final apps = appsState.apps
        .where((app) =>
            !hidden.contains(app.launcherKey) &&
            !hidden.contains(app.packageName) &&
            app.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Material(
      color: Colors.black.withValues(alpha: 0.68),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: TextField(
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search',
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  suffixIcon: IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: apps.length,
                itemBuilder: (context, index) {
                  final app = apps[index];
                  return ListTile(
                    leading: _Icon(app: app, size: 40),
                    title: Text(
                      app.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      widget.onClose();
                      widget.onLaunch(app);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
