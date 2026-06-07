import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../models/app_info.dart';
import '../../models/launcher_settings.dart';
import '../../services/launcher_service.dart';
import '../../state/apps_cubit.dart';
import '../../state/settings_cubit.dart';
import '../../widgets/app_menu/launcher_app_context_menu.dart';
import '../../widgets/wallpaper/themed_wallpaper_background.dart';

class MinimalHomeView extends StatefulWidget {
  final LauncherSettings settings;
  final ValueChanged<AppInfo> onLaunchApp;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenSettings;

  const MinimalHomeView({
    super.key,
    required this.settings,
    required this.onLaunchApp,
    required this.onOpenSearch,
    required this.onOpenSettings,
  });

  @override
  State<MinimalHomeView> createState() => _MinimalHomeViewState();
}

class _MinimalHomeViewState extends State<MinimalHomeView> {
  final _pageController = PageController(initialPage: 1);
  Timer? _timer;
  DateTime _now = DateTime.now();
  int _batteryLevel = -1;
  bool _drawerRouteOpen = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _loadBattery();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background: the device wallpaper (same as the Smart launcher) or a
        // flat solid colour, depending on the Minimal setting.
        if (settings.minimalUseWallpaper) ...[
          ThemedWallpaperBackground(
            path: settings.customWallpaperPath,
            useSystemWallpaper: true,
            transparentSystemFallback: true,
            blur: settings.wallpaperBlur,
            blurSigma: 4 + settings.wallpaperBlurIntensity * 18,
            fallbackColors: const [Colors.black, Colors.black],
          ),
          ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
        ] else
          ColoredBox(color: Color(settings.minimalBackgroundColor)),
        SafeArea(
          child: BlocBuilder<AppsCubit, AppsState>(
            buildWhen: (prev, next) => prev.apps != next.apps,
            builder: (context, appsState) {
              final apps = _visibleApps(appsState.apps, settings);
              final favorites = _favoriteApps(apps, settings);
              return PageView(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                children: [
                  _MinimalDiscoverPage(
                    now: _now,
                    settings: settings,
                    onSettings: widget.onOpenSettings,
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity < -350) _openDrawerPage(apps, settings);
                      if (velocity > 350) widget.onOpenSearch();
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 22, 28, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Spacer(flex: 2),
                          _Clock(now: _now, settings: settings),
                          const SizedBox(height: 10),
                          Text(
                            _dateBatteryText,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.76),
                              fontSize: settings.minimalFontSize,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _DayProgress(settings: settings, now: _now),
                          const Spacer(flex: 2),
                          _FavoritesList(
                            favorites: favorites,
                            fontSize: settings.minimalFontSize,
                            onLaunch: widget.onLaunchApp,
                            onAdd: () => _showFavoritePicker(apps, settings),
                            onLongPress: (app, position) =>
                                _showFavoriteMenu(app, position, settings),
                          ),
                          const Spacer(flex: 4),
                          _MinimalActions(
                            onApps: () => _openDrawerPage(apps, settings),
                            onSearch: widget.onOpenSearch,
                            onSettings: widget.onOpenSettings,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _MinimalLibraryPage(
                    apps: apps,
                    fontSize: settings.minimalFontSize,
                    onLaunch: widget.onLaunchApp,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  String get _dateBatteryText {
    final date = DateFormat('EEEE, MMMM d').format(_now);
    if (_batteryLevel < 0) return date;
    return '$date  -  $_batteryLevel%';
  }

  Future<void> _loadBattery() async {
    final level = await LauncherService.getBatteryLevel();
    if (mounted) setState(() => _batteryLevel = level);
  }

  Future<void> _openDrawerPage(
    List<AppInfo> apps,
    LauncherSettings settings,
  ) async {
    if (_drawerRouteOpen) return;
    _drawerRouteOpen = true;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (routeContext, animation, secondaryAnimation) {
          return _MinimalDrawerPage(
            apps: apps,
            settings: settings,
            fontSize: settings.minimalFontSize,
            onDismiss: () => Navigator.of(routeContext).maybePop(),
            onLaunch: (app) {
              Navigator.of(routeContext).pop();
              widget.onLaunchApp(app);
            },
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final offset = Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          );
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offset, child: child),
          );
        },
      ),
    );
    _drawerRouteOpen = false;
  }

  List<AppInfo> _visibleApps(List<AppInfo> apps, LauncherSettings settings) {
    final hidden = settings.hiddenApps.toSet();
    return apps
        .where((app) =>
            !hidden.contains(app.launcherKey) &&
            !hidden.contains(app.packageName))
        .toList();
  }

  List<AppInfo> _favoriteApps(List<AppInfo> apps, LauncherSettings settings) {
    final refs = settings.minimalFavoritePackages;
    if (refs.isEmpty) return apps.take(6).toList();
    final byKey = {for (final app in apps) app.launcherKey: app};
    final byPackage = {for (final app in apps) app.packageName: app};
    return refs
        .map((ref) => byKey[ref] ?? byPackage[ref])
        .whereType<AppInfo>()
        .toList();
  }

  void _removeFavorite(AppInfo app, LauncherSettings settings) {
    final refs = settings.minimalFavoritePackages
        .where((ref) => ref != app.launcherKey && ref != app.packageName)
        .toList();
    context
        .read<SettingsCubit>()
        .update(settings.copyWith(minimalFavoritePackages: refs));
  }

  Future<void> _showFavoriteMenu(
    AppInfo app,
    Offset position,
    LauncherSettings settings,
  ) {
    return showLauncherAppContextMenu(
      context,
      app: app,
      globalPosition: position,
      trailingItems: [
        LauncherAppMenuItem(
          id: 'remove_favorite',
          icon: Icons.remove_circle_outline,
          label: 'Remove favorite',
          destructive: true,
          onSelected: () => _removeFavorite(app, settings),
        ),
      ],
    );
  }

  void _showFavoritePicker(List<AppInfo> apps, LauncherSettings settings) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final selected = settings.minimalFavoritePackages.toSet();
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return ListView.builder(
              itemCount: apps.length,
              itemBuilder: (context, index) {
                final app = apps[index];
                final checked = selected.contains(app.launcherKey) ||
                    selected.contains(app.packageName);
                return CheckboxListTile(
                  value: checked,
                  title: Text(app.name),
                  onChanged: (value) {
                    setSheetState(() {
                      if (value == true) {
                        selected.add(app.launcherKey);
                      } else {
                        selected
                          ..remove(app.launcherKey)
                          ..remove(app.packageName);
                      }
                    });
                    context.read<SettingsCubit>().update(
                          settings.copyWith(
                            minimalFavoritePackages: selected.toList()..sort(),
                          ),
                        );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _MinimalDiscoverPage extends StatelessWidget {
  final DateTime now;
  final LauncherSettings settings;
  final VoidCallback onSettings;

  const _MinimalDiscoverPage({
    required this.now,
    required this.settings,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Discover',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: settings.minimalFontSize * 1.6,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onSettings,
                color: Colors.white70,
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          const Spacer(),
          Text(
            DateFormat('EEEE').format(now),
            style: TextStyle(
              color: Colors.white,
              fontSize: settings.minimalFontSize * 2.4,
              fontWeight: FontWeight.w200,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            DateFormat('MMMM d, y').format(now),
            style: TextStyle(
              color: Colors.white70,
              fontSize: settings.minimalFontSize,
            ),
          ),
          const SizedBox(height: 26),
          _MinimalInfoLine(
            icon: Icons.schedule_outlined,
            text: 'Swipe right for home',
            fontSize: settings.minimalFontSize,
          ),
          const SizedBox(height: 10),
          _MinimalInfoLine(
            icon: Icons.apps_outlined,
            text: 'Swipe up on home for app drawer',
            fontSize: settings.minimalFontSize,
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class _MinimalInfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final double fontSize;

  const _MinimalInfoLine({
    required this.icon,
    required this.text,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white60, size: fontSize + 4),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: Colors.white70, fontSize: fontSize),
          ),
        ),
      ],
    );
  }
}

class _MinimalLibraryPage extends StatefulWidget {
  final List<AppInfo> apps;
  final double fontSize;
  final ValueChanged<AppInfo> onLaunch;

  const _MinimalLibraryPage({
    required this.apps,
    required this.fontSize,
    required this.onLaunch,
  });

  @override
  State<_MinimalLibraryPage> createState() => _MinimalLibraryPageState();
}

class _MinimalLibraryPageState extends State<_MinimalLibraryPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final apps = _filtered;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Library',
            style: TextStyle(
              color: Colors.white,
              fontSize: widget.fontSize * 1.6,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 18),
          _MinimalSearchField(
            hint: 'Search apps',
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: apps.length,
              itemBuilder: (context, index) {
                final app = apps[index];
                return _MinimalAppTextTile(
                  app: app,
                  fontSize: widget.fontSize,
                  onTap: () => widget.onLaunch(app),
                  onLongPress: (position) => showLauncherAppContextMenu(
                    context,
                    app: app,
                    globalPosition: position,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<AppInfo> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.apps;
    return widget.apps
        .where((app) => app.name.toLowerCase().contains(q))
        .toList();
  }
}

class _MinimalDrawerPage extends StatefulWidget {
  final List<AppInfo> apps;
  final LauncherSettings settings;
  final double fontSize;
  final VoidCallback onDismiss;
  final ValueChanged<AppInfo> onLaunch;

  const _MinimalDrawerPage({
    required this.apps,
    required this.settings,
    required this.fontSize,
    required this.onDismiss,
    required this.onLaunch,
  });

  @override
  State<_MinimalDrawerPage> createState() => _MinimalDrawerPageState();
}

class _MinimalDrawerPageState extends State<_MinimalDrawerPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final apps = _filtered;
    final settings = widget.settings;
    // The drawer gets its own background: the device wallpaper (blurred, with a
    // dark scrim for legibility) when wallpaper mode is on, otherwise the flat
    // solid colour — matching the home background choice.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (settings.minimalUseWallpaper) ...[
          ThemedWallpaperBackground(
            path: settings.customWallpaperPath,
            useSystemWallpaper: true,
            transparentSystemFallback: true,
            blur: true,
            blurSigma: 26,
            fallbackColors: const [Colors.black, Colors.black],
          ),
          ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
        ] else
          ColoredBox(color: Color(settings.minimalBackgroundColor)),
        Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 18, 26, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Apps',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: widget.fontSize * 1.7,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: widget.onDismiss,
                        color: Colors.white70,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _MinimalSearchField(
                    hint: 'Search',
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: apps.length,
                      itemBuilder: (context, index) {
                        final app = apps[index];
                        return _MinimalAppTextTile(
                          app: app,
                          fontSize: widget.fontSize,
                          onTap: () => widget.onLaunch(app),
                          onLongPress: (position) => showLauncherAppContextMenu(
                            context,
                            app: app,
                            globalPosition: position,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<AppInfo> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.apps;
    return widget.apps
        .where((app) => app.name.toLowerCase().contains(q))
        .toList();
  }
}

class _MinimalSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  const _MinimalSearchField({required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: const Icon(Icons.search, color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _MinimalAppTextTile extends StatelessWidget {
  final AppInfo app;
  final double fontSize;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onLongPress;

  const _MinimalAppTextTile({
    required this.app,
    required this.fontSize,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: onLongPress == null
          ? null
          : (details) => onLongPress!(details.globalPosition),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Text(
          app.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize * 1.18,
            fontWeight: FontWeight.w300,
          ),
        ),
      ),
    );
  }
}

class _Clock extends StatelessWidget {
  final DateTime now;
  final LauncherSettings settings;

  const _Clock({required this.now, required this.settings});

  @override
  Widget build(BuildContext context) {
    final pattern = settings.minimalUse24HourClock ? 'HH:mm' : 'h:mm';
    return Text(
      DateFormat(pattern).format(now),
      style: TextStyle(
        color: Colors.white,
        fontSize: settings.minimalFontSize * 4.0,
        fontWeight: FontWeight.w200,
        height: 0.95,
        letterSpacing: 0,
      ),
    );
  }
}

class _DayProgress extends StatelessWidget {
  final LauncherSettings settings;
  final DateTime now;

  const _DayProgress({required this.settings, required this.now});

  @override
  Widget build(BuildContext context) {
    final minutes = now.hour * 60 + now.minute;
    final start = settings.minimalDayStartMinutes;
    final end = settings.minimalDayEndMinutes;
    final span = (end - start).clamp(1, 24 * 60);
    final progress = ((minutes - start) / span).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        minHeight: 4,
        value: progress,
        color: Colors.white,
        backgroundColor: Colors.white.withValues(alpha: 0.18),
      ),
    );
  }
}

class _FavoritesList extends StatelessWidget {
  final List<AppInfo> favorites;
  final double fontSize;
  final ValueChanged<AppInfo> onLaunch;
  final VoidCallback onAdd;
  final void Function(AppInfo app, Offset position) onLongPress;

  const _FavoritesList({
    required this.favorites,
    required this.fontSize,
    required this.onLaunch,
    required this.onAdd,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final app in favorites)
          GestureDetector(
            onTap: () => onLaunch(app),
            onLongPressStart: (details) =>
                onLongPress(app, details.globalPosition),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(
                app.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize * 1.35,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Apps'),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
        ),
      ],
    );
  }
}

class _MinimalActions extends StatelessWidget {
  final VoidCallback onApps;
  final VoidCallback onSearch;
  final VoidCallback onSettings;

  const _MinimalActions({
    required this.onApps,
    required this.onSearch,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ActionButton(icon: Icons.apps_rounded, onTap: onApps),
        _ActionButton(icon: Icons.search_rounded, onTap: onSearch),
        _ActionButton(icon: Icons.settings_outlined, onTap: onSettings),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onTap,
      color: Colors.white,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.12),
      ),
      icon: Icon(icon),
    );
  }
}
