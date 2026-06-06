import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/app_info.dart';
import '../../models/launcher_settings.dart';
import '../../services/app_categories.dart';
import '../../services/launcher_service.dart';
import '../../state/apps_cubit.dart';
import '../../state/settings_cubit.dart';
import '../../widgets/icons/feature_icon.dart';
import '../../widgets/icons/shaped_icon.dart';
import '../../widgets/wallpaper/themed_wallpaper_background.dart';

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
  final _pageController = PageController();
  int _currentPage = 0;
  bool _editMode = false;
  bool _libraryOpen = false;
  bool _searchOpen = false;

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
          fallbackColors: const [Color(0xFF1A2440), Color(0xFF9C6F72)],
        ),
        SafeArea(
          child: BlocBuilder<AppsCubit, AppsState>(
            buildWhen: (prev, next) => prev.apps != next.apps,
            builder: (context, appsState) {
              final apps = _visibleApps(appsState.apps, settings);
              final pages = _pages(apps, settings);
              final dock = _dockApps(apps, settings);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: _showHomeOptions,
                onTap: _editMode ? _exitEditMode : null,
                onVerticalDragEnd: (details) {
                  if (_editMode) return;
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity > 420) setState(() => _searchOpen = true);
                  if (velocity < -420) setState(() => _libraryOpen = true);
                },
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        physics: _editMode
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics(),
                        itemCount: pages.length.clamp(1, 999),
                        onPageChanged: (value) =>
                            setState(() => _currentPage = value),
                        itemBuilder: (context, index) {
                          final page = pages.isEmpty
                              ? const _IosPage.empty()
                              : pages[index];
                          return _IosPageView(
                            page: page,
                            settings: settings,
                            editMode: _editMode,
                            jiggle: _jiggle,
                            onLaunch: widget.onLaunchApp,
                            onLaunchTemplate: _launchTemplateApp,
                            onLongPress: _showAppMenuAt,
                            onRemove: _hideApp,
                          );
                        },
                      ),
                    ),
                    _PageDots(count: pages.length, current: _currentPage),
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
                    SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
                  ],
                ),
              );
            },
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
        if (_libraryOpen)
          _IosAppLibrary(
            settings: settings,
            onClose: () => setState(() => _libraryOpen = false),
            onLaunch: widget.onLaunchApp,
            onLongPress: (app) => _showAppMenuAt(app, Offset.zero),
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

  List<AppInfo> _visibleApps(List<AppInfo> apps, LauncherSettings settings) {
    final hidden = settings.hiddenApps.toSet();
    return apps
        .where((app) =>
            !hidden.contains(app.launcherKey) &&
            !hidden.contains(app.packageName))
        .toList();
  }

  List<_IosPage> _pages(List<AppInfo> apps, LauncherSettings settings) {
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
        .where((app) => !templatePackages.contains(app.packageName))
        .toList();
    final columns = settings.iosGridColumns.clamp(3, 5).toInt();
    final size = columns * 5;
    // The first page also shows the widgets row, so it holds fewer icons
    // (two rows) to keep it from feeling cramped. The rest flow onto
    // subsequent full-height pages.
    final firstPageCount = columns * 2;
    final pages = <_IosPage>[
      _IosPage(
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
  final List<_IosTemplateApp> templateApps;
  final bool showWidgets;

  const _IosPage({
    this.apps = const [],
    this.templateApps = const [],
    this.showWidgets = false,
  });

  const _IosPage.empty()
      : apps = const [],
        templateApps = const [],
        showWidgets = false;
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
  final ValueChanged<AppInfo> onLaunch;
  final void Function(AppInfo app, Offset globalPosition) onLongPress;
  final ValueChanged<AppInfo> onRemove;

  const _IconGrid({
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
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: settings.dockBackgroundColor.withValues(
              alpha: settings.dockBackgroundOpacity,
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: row,
        ),
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

  const _IosContextMenuOverlay({
    required this.globalPosition,
    required this.appName,
    required this.inDock,
    required this.dockFull,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const menuW = 220.0;
    const itemH = 48.0;
    const arrowH = 10.0;
    const menuH = itemH * 4 + 2;
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
                    _MenuCard(inDock: inDock, dockFull: dockFull),
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

  const _MenuCard({required this.inDock, required this.dockFull});

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: ColoredBox(
            color: Colors.white.withValues(alpha: 0.14),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: ColoredBox(
            color: Colors.white.withValues(alpha: 0.14),
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

class _IosAppLibrary extends StatelessWidget {
  final LauncherSettings settings;
  final VoidCallback onClose;
  final ValueChanged<AppInfo> onLaunch;
  final ValueChanged<AppInfo> onLongPress;

  const _IosAppLibrary({
    required this.settings,
    required this.onClose,
    required this.onLaunch,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final appsState = context.watch<AppsCubit>().state;
    final hidden = settings.hiddenApps.toSet();
    final apps = appsState.apps
        .where((app) =>
            !hidden.contains(app.launcherKey) &&
            !hidden.contains(app.packageName))
        .toList();
    final buckets = categorizeApps(apps);
    return Material(
      color: Colors.black.withValues(alpha: 0.86),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    const Text(
                      'App Library',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            if (settings.iosLibraryViewMode == IosLibraryViewMode.list)
              SliverList.builder(
                itemCount: apps.length,
                itemBuilder: (context, index) {
                  final app = apps[index];
                  return ListTile(
                    leading: _Icon(app: app, size: 42),
                    title: Text(
                      app.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      onClose();
                      onLaunch(app);
                    },
                    onLongPress: () => onLongPress(app),
                  );
                },
              )
            else
              for (final entry in buckets.entries)
                if (entry.value.isNotEmpty) ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        entry.key.label,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.78,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final app = entry.value[index];
                          return _IosAppTile(
                            app: app,
                            settings: settings,
                            editMode: false,
                            jiggle: const AlwaysStoppedAnimation(0),
                            index: index,
                            onTap: () {
                              onClose();
                              onLaunch(app);
                            },
                            onLongPress: (_) => onLongPress(app),
                            onRemove: () {},
                          );
                        },
                        childCount: entry.value.length,
                      ),
                    ),
                  ),
                ],
            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        ),
      ),
    );
  }
}
