import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smart_launcher_app/core/storage/mini_app_repositories.dart';
import 'package:smart_launcher_app/core/models/app_info.dart';
import 'package:smart_launcher_app/core/models/launcher_feature.dart';
import 'package:smart_launcher_app/core/models/launcher_feature_settings.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/features/apps/presentation/bloc/apps_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/launcher_feature_cubit.dart';
import 'package:smart_launcher_app/core/widgets/icons/shaped_icon.dart';
import 'package:smart_launcher_app/features/app_lock/presentation/screens/app_lock_lock_screen.dart';
import 'package:smart_launcher_app/features/app_lock/presentation/screens/app_lock_onboarding.dart';
import 'package:smart_launcher_app/features/app_lock/presentation/screens/app_lock_protection_guide.dart';
import 'package:smart_launcher_app/features/onboarding/data/onboarding_store.dart';
import 'package:smart_launcher_app/features/app_lock/presentation/screens/app_lock_settings_screen.dart';
import 'package:smart_launcher_app/features/clock/presentation/clock_theme.dart';
import 'package:smart_launcher_app/core/widgets/mini_app_chrome.dart';
import 'package:smart_launcher_app/core/widgets/mini_app_kit.dart';

/// App Lock: a monochrome (alarm-themed) per-app locker. Gates on entry behind
/// its own PIN/pattern + fingerprint (see [AppLockLockScreen]) exactly like the
/// Vault, then lists apps under Locked / All tabs. Enforcement is native: apps
/// launched from the launcher lock instantly, and a Usage-access watcher covers
/// apps opened anywhere else, device-wide.
class AppLockerScreen extends StatefulWidget {
  const AppLockerScreen({super.key});

  @override
  State<AppLockerScreen> createState() => _AppLockerScreenState();
}

class _AppLockerScreenState extends State<AppLockerScreen>
    with WidgetsBindingObserver {
  final _sec = AppLockSecurityRepository();
  var _unlocked = false;
  var _query = '';
  var _usageAccess = false;
  var _overlay = false;
  var _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_sec.isConfigured && _sec.withinGrace) _unlocked = true;
    _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    _refreshPermissions();
    // Keep the current unlock while this screen is alive. Android also sends
    // resumed after permission screens, so re-locking here makes normal setup
    // actions feel random.
  }

  Future<void> _refreshPermissions() async {
    final usageAccess = await LauncherService.isUsageAccessEnabled();
    final overlay = await LauncherService.canDrawOverlays();
    if (!mounted) return;
    setState(() {
      _usageAccess = usageAccess;
      _overlay = overlay;
    });
  }

  // Overlay draws the lock; Usage access adds the outside-launcher fallback.
  // Both granted ⇒ fully protected device-wide.
  bool get _ready => _overlay && _usageAccess;

  void _openGuide() {
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) => const AppLockProtectionGuide()))
        .then((_) {
      if (mounted) _refreshPermissions();
    });
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AppLockSettingsScreen()))
        .then((_) {
      if (!mounted) return;
      // If the user turned App Lock off in settings, drop back to setup.
      if (!_sec.isConfigured) {
        setState(() => _unlocked = false);
      } else {
        _refreshPermissions();
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!OnboardingStore.isMiniAppOnboardedSync('app_locker')) {
      return AppLockOnboarding(
        onContinue: () {
          OnboardingStore.markMiniAppOnboarded('app_locker');
          setState(() {});
        },
        onBack: () => Navigator.of(context).pop(),
      );
    }
    if (!_unlocked) {
      return AppLockLockScreen(
        security: _sec,
        onUnlocked: () => setState(() => _unlocked = true),
        onCancel: () => Navigator.of(context).pop(),
      );
    }

    return DefaultTabController(
      length: 2,
      child: MiniAppScaffold(
        title: 'App Locker',
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
              return BlocBuilder<LauncherFeatureSettingsCubit,
                  LauncherFeatureSettings>(
                builder: (context, featureSettings) {
                  final locked = featureSettings.lockedApps.toSet();
                  final all = appsState.apps
                      .where((app) => !LauncherFeatureCatalog.isFeatureApp(app))
                      .where(_matchesQuery)
                      .toList(growable: false);
                  final lockedApps = all
                      .where((app) => locked.contains(app.packageName))
                      .toList(growable: false);
                  final tabApps = _tabIndex == 0 ? all : lockedApps;
                  final emptyHint = _tabIndex == 0
                      ? 'No apps match your search.'
                      : locked.isEmpty
                          ? 'No apps locked yet. Add some from the All apps tab.'
                          : 'No locked apps match your search.';
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                    children: [
                      if (_ready)
                        _statusCard(locked.length)
                      else
                        _offBanner(),
                      const SizedBox(height: 12),
                      _searchField(),
                      const SizedBox(height: 8),
                      TabBar(
                        onTap: (index) => setState(() => _tabIndex = index),
                        labelColor: Colors.white,
                        unselectedLabelColor: miniAppMuted,
                        indicatorColor: Colors.white,
                        tabs: const [
                          Tab(text: 'All apps'),
                          Tab(text: 'Locked'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ..._appListItems(tabApps, locked, emptyHint: emptyHint),
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

  List<Widget> _appListItems(
    List<AppInfo> apps,
    Set<String> locked, {
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
        _AppLockTile(
          app: app,
          locked: locked.contains(app.packageName),
          onChanged: (value) => context
              .read<LauncherFeatureSettingsCubit>()
              .setAppLocked(app.packageName, value),
        ),
    ];
  }

  /// Shown once the service + overlay are granted: a calm "active" summary.
  Widget _statusCard(int lockedCount) {
    return RoundCard(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.lock, color: clockAccent, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'App Lock is active',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '$lockedCount app${lockedCount == 1 ? '' : 's'} locked behind your passcode.',
                  style: const TextStyle(color: miniAppMuted, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Shown until protection is complete. If the overlay alone is granted, apps
  /// opened from the launcher already lock — so it shifts to an "almost there"
  /// nudge to add app detection; with neither, a full OFF warning. Tapping
  /// opens the guided setup flow.
  Widget _offBanner() {
    final warn = accentForFeature('app_locker');
    final partial = _overlay && !_usageAccess;
    final title = partial ? 'Almost protected' : 'App Lock is OFF';
    final subtitle = partial
        ? 'Apps you open from your home screen are locked. Turn on app detection '
            'to also lock apps opened elsewhere.'
        : 'Your locked apps are NOT protected. Tap to turn on protection.';
    return RoundCard(
      onTap: _openGuide,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: warn.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.gpp_maybe, color: warn, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: warn),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: miniAppMuted, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: miniAppMuted),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: TextField(
        onChanged: (value) => setState(() => _query = value),
        decoration: InputDecoration(
          hintText: 'Search apps',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: miniAppSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _AppLockTile extends StatelessWidget {
  final AppInfo app;
  final bool locked;
  final ValueChanged<bool> onChanged;

  const _AppLockTile({
    required this.app,
    required this.locked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 3),
      leading: ShapedIcon(
        iconBytes: app.icon,
        iconPath: app.iconPath,
        shape: 'squircle',
        size: 44,
        cacheKey: app.packageName,
      ),
      title: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        locked ? 'Locked' : app.packageName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: miniAppMuted),
      ),
      trailing: Switch(value: locked, onChanged: onChanged),
    );
  }
}
