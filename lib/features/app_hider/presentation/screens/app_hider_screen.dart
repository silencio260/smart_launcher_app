import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/mini_app_repositories.dart';
import '../../models/app_info.dart';
import '../../models/launcher_feature.dart';
import '../../models/launcher_settings.dart';
import '../../state/apps_cubit.dart';
import '../../state/settings_cubit.dart';
import '../../widgets/icons/shaped_icon.dart';
import 'app_hider/app_hider_lock_screen.dart';
import 'app_hider/app_hider_settings_screen.dart';
import 'clock/clock_theme.dart';
import 'mini_app_chrome.dart';
import 'mini_app_kit.dart';

const _featureId = 'app_hider';

/// App Hider: a monochrome (alarm-themed) hidden space. Gates on entry behind
/// its own PIN/pattern + fingerprint (see [AppHiderLockScreen]) exactly like the
/// Vault and App Lock, then lists apps under All apps / Hidden apps tabs. Hidden
/// apps drop out of the drawer and search via [LauncherSettings.hiddenApps].
class AppHiderScreen extends StatefulWidget {
  const AppHiderScreen({super.key});

  @override
  State<AppHiderScreen> createState() => _AppHiderScreenState();
}

class _AppHiderScreenState extends State<AppHiderScreen> {
  final _sec = AppHiderSecurityRepository();
  var _unlocked = false;
  var _query = '';
  var _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    if (_sec.isConfigured && _sec.withinGrace) _unlocked = true;
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) => const AppHiderSettingsScreen()))
        .then((_) {
      if (!mounted) return;
      // If the user turned the passcode off in settings, drop back to setup.
      if (!_sec.isConfigured) {
        setState(() => _unlocked = false);
      } else {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_unlocked) {
      return AppHiderLockScreen(
        security: _sec,
        onUnlocked: () => setState(() => _unlocked = true),
        onCancel: () => Navigator.of(context).pop(),
      );
    }

    return DefaultTabController(
      length: 2,
      child: MiniAppScaffold(
        title: 'App Hider',
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: _openSettings,
          ),
        ],
        child: Theme(
          data: clockThemeOf(context),
          child: BlocBuilder<AppsCubit, AppsState>(
            builder: (context, appsState) {
              return BlocBuilder<SettingsCubit, LauncherSettings>(
                builder: (context, settings) {
                  final hidden = settings.hiddenApps.toSet();
                  final allApps = appsState.apps
                      .where((app) => !LauncherFeatureCatalog.isFeatureApp(app))
                      .where(_matchesQuery)
                      .toList(growable: false);
                  final hiddenApps = allApps
                      .where((app) => _isHidden(app, hidden))
                      .toList(growable: false);
                  final tabApps = _tabIndex == 0 ? allApps : hiddenApps;
                  final hiddenCount = hidden.length;
                  final emptyHint = _tabIndex == 0
                      ? 'No apps match your search.'
                      : hidden.isEmpty
                          ? 'No apps hidden yet. Add some from the All apps tab.'
                          : 'No hidden apps match your search.';
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                    children: [
                      MiniHeroCard(
                        featureId: _featureId,
                        title: 'Hidden Space',
                        subtitle:
                            '$hiddenCount app${hiddenCount == 1 ? '' : 's'} invisible from drawer and search.',
                      ),
                      const SizedBox(height: 14),
                      _searchField(),
                      const SizedBox(height: 8),
                      TabBar(
                        onTap: (index) => setState(() => _tabIndex = index),
                        labelColor: Colors.white,
                        unselectedLabelColor: miniAppMuted,
                        indicatorColor: Colors.white,
                        tabs: const [
                          Tab(text: 'All apps'),
                          Tab(text: 'Hidden apps'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ..._appListItems(tabApps, hidden, emptyHint: emptyHint),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  bool _matchesQuery(AppInfo app) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return app.name.toLowerCase().contains(q) ||
        app.packageName.toLowerCase().contains(q);
  }

  bool _isHidden(AppInfo app, Set<String> hidden) {
    return hidden.contains(app.launcherKey) || hidden.contains(app.packageName);
  }

  List<Widget> _appListItems(
    List<AppInfo> apps,
    Set<String> hidden, {
    required String emptyHint,
  }) {
    if (apps.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 48),
          child: Center(
            child: Text(
              emptyHint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: miniAppMuted, height: 1.35),
            ),
          ),
        ),
      ];
    }
    return [
      for (final app in apps)
        _HiddenSpaceTile(
          app: app,
          hidden: _isHidden(app, hidden),
          onChanged: (value) => _setHidden(app, value),
        ),
    ];
  }

  Widget _searchField() {
    return TextField(
      onChanged: (value) => setState(() => _query = value),
      decoration: InputDecoration(
        hintText: 'Search apps to hide',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: miniAppSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  void _setHidden(AppInfo app, bool value) {
    final cubit = context.read<SettingsCubit>();
    final settings = cubit.state;
    final hidden = settings.hiddenApps.toSet();
    hidden.remove(app.packageName);
    hidden.remove(app.launcherKey);
    if (value) hidden.add(app.launcherKey);
    cubit.update(settings.copyWith(hiddenApps: hidden.toList()..sort()));
  }
}

class _HiddenSpaceTile extends StatelessWidget {
  final AppInfo app;
  final bool hidden;
  final ValueChanged<bool> onChanged;

  const _HiddenSpaceTile({
    required this.app,
    required this.hidden,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 2),
      secondary: ShapedIcon(
        iconBytes: app.icon,
        iconPath: app.iconPath,
        shape: 'squircle',
        size: 44,
        cacheKey: app.packageName,
      ),
      title: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        hidden ? 'Hidden' : app.packageName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: miniAppMuted),
      ),
      value: hidden,
      onChanged: onChanged,
    );
  }
}
