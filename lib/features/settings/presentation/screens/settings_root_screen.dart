import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smart_launcher_app/core/analytics/app_events.dart';
import 'package:smart_launcher_app/core/ads/test_ads_config.dart';
import 'package:smart_launcher_app/core/config/app_env.dart';
import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/core/models/launcher_widget_info.dart';
import 'package:smart_launcher_app/core/storage/mini_app_repositories.dart';
import 'package:smart_launcher_app/features/after_call/data/after_call_service.dart';
import 'package:smart_launcher_app/features/install_assistant/data/install_assistant_service.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/features/apps/presentation/bloc/apps_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:smart_launcher_app/features/home/presentation/bloc/workspace_cubit.dart';
import 'package:smart_launcher_app/features/home/data/default_layout_seeder.dart';
import 'package:smart_launcher_app/core/utils/debug_flags.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/analytics_debug_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/ads_debug_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_launcher_app/core/icons/decoded_icon_cache.dart';
import 'package:smart_launcher_app/features/apps/data/app_snapshot_cache.dart';
import 'package:smart_launcher_app/features/home/data/seed_flags.dart';
import 'package:smart_launcher_app/features/onboarding/data/onboarding_store.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/screens/onboarding_debug_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/general_settings_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/home_screen_settings_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/launcher_themes_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/settings_appearance.dart';
// Smartspace settings screen removed (dead Calendar Events toggle).
// import 'package:smart_launcher_app/features/settings/presentation/screens/smartspace_settings_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/dock_settings_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/drawer_settings_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/folder_settings_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/gesture_settings_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/recents_settings_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/help_feedback_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/widget_picker_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/wallpaper_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/support_links.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/launcher_features_settings_screen.dart';

class SettingsRootScreen extends StatefulWidget {
  final void Function(LauncherWidgetInfo widget, int page)? onWidgetAdded;

  const SettingsRootScreen({super.key, this.onWidgetAdded});

  @override
  State<SettingsRootScreen> createState() => _SettingsRootScreenState();
}

class _SettingsRootScreenState extends State<SettingsRootScreen> {
  @override
  void initState() {
    super.initState();
    AppAnalytics.settingsOpened();
    if (DebugFlags.settingsLogs) {
      debugPrint('SettingsLog SettingsRootScreen opened');
    }
  }

  @override
  void dispose() {
    if (DebugFlags.settingsLogs) {
      debugPrint('SettingsLog SettingsRootScreen closed');
    }
    super.dispose();
  }

  /// Clears all settings and home-screen layout back to defaults. Moved here
  /// from the (now removed) Backup & Restore screen so the destructive reset
  /// lives behind Developer Options.
  ///
  /// Resetting settings alone wipes [LauncherSettings.dockPackages] to an empty
  /// list (its model default) and leaves the persisted page layout untouched,
  /// which left the dock blank. So after clearing settings we re-run the
  /// [DefaultLayoutSeeder], which rebuilds both the pages and the dock from the
  /// installed apps — the same coherent default the first-run seed produces.
  void _confirmReset(BuildContext context) {
    final settingsCubit = context.read<SettingsCubit>();
    final appsCubit = context.read<AppsCubit>();
    final workspaceCubit = context.read<WorkspaceCubit>();
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: const Text(
          'This will clear all your settings and rebuild the home screen and '
          'dock from your installed apps. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogContext);
              final apps = appsCubit.state.apps;
              if (apps.isEmpty) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Apps are still loading — try again.'),
                  ),
                );
                return;
              }
              await settingsCubit.reset();
              DefaultLayoutSeeder.seed(
                apps: apps,
                workspace: workspaceCubit,
                settings: settingsCubit,
              );
              messenger.showSnackBar(
                const SnackBar(content: Text('Reset to defaults.')),
              );
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  /// Dev View: wipe everything a genuine fresh install lacks — cached icons,
  /// the app snapshot, the seeded-layout flags, the persisted layout, all
  /// settings, and onboarding flags — then restart the app at the onboarding
  /// flow. Lets us re-experience (and test) the first-run "Setting up your
  /// launcher" path without uninstalling.
  void _confirmSimulateFreshInstall(BuildContext context) {
    final settingsCubit = context.read<SettingsCubit>();
    final workspaceCubit = context.read<WorkspaceCubit>();
    final appsCubit = context.read<AppsCubit>();
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Simulate Fresh Install'),
        content: const Text(
          'This clears all cached app icons, the app snapshot, your home '
          'screen layout, all settings, and onboarding flags — then restarts '
          'at the onboarding flow as if the launcher were just installed. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _runSimulateFreshInstall(
                settingsCubit: settingsCubit,
                workspaceCubit: workspaceCubit,
                appsCubit: appsCubit,
              );
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                (route) => false,
              );
            },
            child: const Text('Simulate'),
          ),
        ],
      ),
    );
  }

  Future<void> _runSimulateFreshInstall({
    required SettingsCubit settingsCubit,
    required WorkspaceCubit workspaceCubit,
    required AppsCubit appsCubit,
  }) async {
    // On-disk + in-memory caches that make a warm start instant.
    await AppSnapshotCache.instance.clear();
    await LauncherService.clearIconCaches();
    DecodedIconCache.instance.clear();

    // First-run flags + persisted layout, so the default layout re-seeds and
    // the onboarding flow replays on the next launch.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kDefaultLayoutSeededFlag);
    await prefs.remove(kFeatureIconsSeededFlag);
    await prefs.remove(kWorkspaceLayoutKey);
    await OnboardingStore.resetCompleted();
    await OnboardingStore.resetNudge();
    for (final id in kMiniAppOnboardingIds) {
      await OnboardingStore.resetMiniAppOnboarded(id);
    }

    // Reset the live cubits so the running process reflects the wipe without a
    // cold restart: settings → defaults, workspace → empty (fresh-install), and
    // apps → reload from scratch (drives the home initializing cover).
    settingsCubit.reset();
    await workspaceCubit.loadLayout();
    await appsCubit.resetForFreshInstall();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsAppearance(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Launcher Settings'),
        ),
        body: Builder(
          builder: (context) {
            final items = <WidgetBuilder>[
              (c) => _Tile(
                    icon: Icons.tune,
                    title: 'General',
                    subtitle: 'Theme, icons, badges',
                    onTap: () => Navigator.push(
                      c,
                      settingsRoute(const GeneralSettingsScreen()),
                    ),
                  ),
              (c) => _Tile(
                    icon: Icons.format_paint_outlined,
                    title: 'Themes',
                    subtitle: 'Smart, iOS, and Minimal launchers',
                    onTap: () => Navigator.push(
                      c,
                      settingsRoute(const LauncherThemesScreen()),
                    ),
                  ),
              (c) => _Tile(
                    icon: Icons.wallpaper_outlined,
                    title: 'Wallpaper',
                    subtitle: 'Browse, download, and apply wallpapers',
                    onTap: () => Navigator.push(
                      c,
                      settingsRoute(const WallpaperScreen()),
                    ),
                  ),
              (c) => _Tile(
                    icon: Icons.home_outlined,
                    title: 'Home Screen',
                    subtitle: 'Grid, layout, wallpaper',
                    onTap: () => Navigator.push(
                      c,
                      settingsRoute(const HomeScreenSettingsScreen()),
                    ),
                  ),
              (c) => _Tile(
                    icon: Icons.widgets_outlined,
                    title: 'Widgets',
                    subtitle: 'Browse and add home screen widgets',
                    onTap: () => Navigator.push(
                      c,
                      settingsRoute(
                        WidgetPickerScreen(onWidgetAdded: widget.onWidgetAdded),
                      ),
                    ),
                  ),
              // Smartspace settings screen removed: it exposed the dead
              // Calendar Events toggle. (Its working bits — time format / next
              // alarm — fall back to defaults.) Re-add when reinstated.
              // (c) => _Tile(
              //       icon: Icons.wb_sunny_outlined,
              //       title: 'Smartspace',
              //       subtitle: 'Clock, date, cards',
              //       onTap: () => Navigator.push(
              //         c,
              //         settingsRoute(const SmartspaceSettingsScreen()),
              //       ),
              //     ),
              (c) => _Tile(
                    icon: Icons.dock,
                    title: 'Dock',
                    subtitle: 'Dock appearance and size',
                    onTap: () => Navigator.push(
                      c,
                      settingsRoute(const DockSettingsScreen()),
                    ),
                  ),
              (c) => _Tile(
                    icon: Icons.apps,
                    title: 'App Drawer',
                    subtitle: 'Layout, columns, hidden apps',
                    onTap: () => Navigator.push(
                      c,
                      settingsRoute(const DrawerSettingsScreen()),
                    ),
                  ),
              (c) => _Tile(
                    icon: Icons.auto_awesome_outlined,
                    title: 'Launcher Features',
                    subtitle: 'Feature apps, overlays, after-call tools',
                    onTap: () => Navigator.push(
                      c,
                      settingsRoute(const LauncherFeaturesSettingsScreen()),
                    ),
                  ),
              (c) => _Tile(
                    icon: Icons.folder_outlined,
                    title: 'Folders',
                    subtitle: 'Folder style and grid size',
                    onTap: () => Navigator.push(
                      c,
                      settingsRoute(const FolderSettingsScreen()),
                    ),
                  ),
              (c) => _Tile(
                    icon: Icons.swipe,
                    title: 'Gestures',
                    subtitle: 'Swipes, double-tap, buttons',
                    onTap: () => Navigator.push(
                      c,
                      settingsRoute(const GestureSettingsScreen()),
                    ),
                  ),
              (c) => _Tile(
                    icon: Icons.history,
                    title: 'Recents',
                    subtitle: 'Recent apps behavior',
                    onTap: () => Navigator.push(
                      c,
                      settingsRoute(const RecentsSettingsScreen()),
                    ),
                  ),
              (_) => const Divider(),
              (_) => const _SectionHeader(
                    icon: Icons.support_outlined,
                    title: 'Support',
                  ),
              (c) => _Tile(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy Policy',
                    subtitle: 'How your data is handled',
                    onTap: () async {
                      final ok = await LauncherService.launchUrl(
                          SupportLinks.privacyPolicyUrl);
                      if (!c.mounted) return;
                      if (!ok) {
                        ScaffoldMessenger.of(c)
                          ..removeCurrentSnackBar()
                          ..showSnackBar(const SnackBar(
                              content:
                                  Text("Couldn't open the privacy policy")));
                      }
                    },
                  ),
              (c) => _Tile(
                    icon: Icons.help_outline,
                    title: 'Help & Feedback',
                    subtitle: 'Restore home screen, send feedback, uninstall',
                    onTap: () => Navigator.push(
                      c,
                      settingsRoute(const HelpFeedbackScreen()),
                    ),
                  ),
              // The entire Developer Options section is hidden outside a
              // development build. We gate on AppEnv.developmentMode (set by
              // dev.json / special_dev.json) rather than kDebugMode, because a
              // debug binary can be run against release env files — in that
              // case developmentMode is false and the section must not show.
              // Individual tiles below add their own finer-grained guards.
              if (AppEnv.developmentMode) ...[
              (_) => const Divider(),
              (_) => const _SectionHeader(
                    icon: Icons.science_outlined,
                    title: 'Developer Options',
                  ),
              (_) => const _SubSectionHeader(
                    icon: Icons.build_outlined,
                    title: 'Maintenance',
                  ),
              (c) => ListTile(
                    leading: const Icon(Icons.restore, color: Colors.red),
                    title: const Text('Reset to Defaults',
                        style: TextStyle(color: Colors.red)),
                    subtitle: const Text('Clear all settings and layout'),
                    onTap: () => _confirmReset(c),
                  ),
              (c) => ListTile(
                    leading: const Icon(Icons.cleaning_services_outlined,
                        color: Colors.red),
                    title: const Text('Simulate Fresh Install',
                        style: TextStyle(color: Colors.red)),
                    subtitle: const Text(
                      'Wipe icon caches, snapshot, layout, settings & '
                      'onboarding, then restart at onboarding',
                    ),
                    onTap: () => _confirmSimulateFreshInstall(c),
                  ),
              (_) => const _SubSectionHeader(
                    icon: Icons.visibility_outlined,
                    title: 'Dev View',
                  ),
              (c) => BlocBuilder<SettingsCubit, LauncherSettings>(
                    bloc: c.read<SettingsCubit>(),
                    builder: (context, state) {
                      final cubit = context.read<SettingsCubit>();
                      return Column(
                        children: [
                          SwitchListTile(
                            secondary: const Icon(Icons.bug_report_outlined),
                            title: const Text('Grid Debug Overlay'),
                            subtitle: const Text(
                              'Show free cells in green and blocked or occupied cells in red',
                            ),
                            value: state.showGridDebugOverlay,
                            onChanged: (value) => cubit.update(
                              state.copyWith(showGridDebugOverlay: value),
                            ),
                          ),
                          SwitchListTile(
                            secondary: const Icon(Icons.info_outline),
                            title: const Text('Widget Picker Debug Info'),
                            subtitle: const Text(
                              'Show min/max spans, dp sizes, and resize mode under each widget in the picker',
                            ),
                            value: state.showWidgetPickerDebugInfo,
                            onChanged: (value) => cubit.update(
                              state.copyWith(showWidgetPickerDebugInfo: value),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
              if (kDebugMode)
                (c) => _Tile(
                      icon: Icons.analytics_outlined,
                      title: 'Analytics',
                      subtitle: 'Retention metrics & tracked events catalog',
                      onTap: () => Navigator.push(
                        c,
                        settingsRoute(const AnalyticsDebugScreen()),
                      ),
                    ),
              if (kDebugMode)
                (c) => _Tile(
                      icon: Icons.flag_outlined,
                      title: 'Onboarding',
                      subtitle: 'Preview & reset first-run and mini-app flows',
                      onTap: () => Navigator.push(
                        c,
                        settingsRoute(const OnboardingDebugScreen()),
                      ),
                    ),
              if (TestAdsConfig.shouldShowDebugEntry())
                (c) => _Tile(
                      icon: Icons.ad_units_outlined,
                      title: 'Ads',
                      subtitle: 'Test ads loader and lifecycle events',
                      onTap: () => Navigator.push(
                        c,
                        settingsRoute(const AdsDebugScreen()),
                      ),
                    ),
              // TEMP: After Call is disabled; keep the debug panel out of Dev
              // View so it cannot arm or preview the paused feature.
              // if (kDebugMode) (_) => const _AfterCallDebugPanel(),
              // TEMP: Install & Uninstall Assistant is disabled; keep the debug
              // panel out of Dev View so it cannot preview the paused feature.
              // if (kDebugMode) (_) => const _InstallAssistantDebugPanel(),
              if (kDebugMode) (_) => const _AlarmDebugPanel(),
              // Crashlytics collection is disabled in debug (see main.dart),
              // so this panel can't actually exercise reporting; it's kept here
              // only for local inspection and rides the section-wide
              // developmentMode guard above so it never ships. Temporary —
              // strip before launch.
              (_) => const _SubSectionHeader(
                    icon: Icons.warning_amber_outlined,
                    title: 'Crashlytics',
                  ),
              (_) => const _CrashlyticsDebugPanel(),
              (_) => const _SubSectionHeader(
                    icon: Icons.article_outlined,
                    title: 'Logs',
                  ),
              (c) => BlocBuilder<SettingsCubit, LauncherSettings>(
                    bloc: c.read<SettingsCubit>(),
                    builder: (context, state) {
                      final cubit = context.read<SettingsCubit>();
                      return Column(
                        children: [
                          SwitchListTile(
                            secondary: const Icon(Icons.article_outlined),
                            title: const Text('Widget Debug Logs'),
                            subtitle: const Text(
                              'Print widget sizing/resize/binding logs to logcat and the Dart console',
                            ),
                            value: state.showWidgetDebugLogs,
                            onChanged: (value) => cubit.update(
                              state.copyWith(showWidgetDebugLogs: value),
                            ),
                          ),
                          SwitchListTile(
                            secondary: const Icon(Icons.open_with_outlined),
                            title: const Text('Widget Drag Debug Logs'),
                            subtitle: const Text(
                              'Log widget long-press, drag activation, drop resolution, placement invariants, and native host-view movement (tags JUMP and WidgetDragDrop)',
                            ),
                            value: state.showWidgetDragDebugLogs,
                            onChanged: (value) => cubit.update(
                              state.copyWith(showWidgetDragDebugLogs: value),
                            ),
                          ),
                          SwitchListTile(
                            secondary: const Icon(Icons.speed_outlined),
                            title: const Text('Drawer Perf Logs'),
                            subtitle: const Text(
                              'Log drawer open timing, per-frame build/raster, and recycler layout/paint events to logcat (tag DrawerPerf)',
                            ),
                            value: state.showDrawerPerfLogs,
                            onChanged: (value) => cubit.update(
                              state.copyWith(showDrawerPerfLogs: value),
                            ),
                          ),
                          SwitchListTile(
                            secondary: const Icon(Icons.layers_outlined),
                            title: const Text('Route Coverage Logs'),
                            subtitle: const Text(
                              'Log when another route covers/uncovers the home screen (tag DrawerPerf RouteCoverage)',
                            ),
                            value: state.showRouteCoverageLogs,
                            onChanged: (value) => cubit.update(
                              state.copyWith(showRouteCoverageLogs: value),
                            ),
                          ),
                          SwitchListTile(
                            secondary: const Icon(Icons.settings_outlined),
                            title: const Text('Settings Logs'),
                            subtitle: const Text(
                              'Log when the Settings screen opens and closes (tag SettingsLog)',
                            ),
                            value: state.showSettingsLogs,
                            onChanged: (value) => cubit.update(
                              state.copyWith(showSettingsLogs: value),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ];
            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (c, i) => items[i](c),
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A nested header that reads as a child of the [_SectionHeader] above it:
/// indented past the parent, smaller, and muted.
class _SubSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SubSectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 12, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Debug-only control for exercising the after-call feature without placing a
/// real call: show the overlay on demand and watch the live status. Arming the
/// call listener is automatic (driven by the "Post-call action center" toggle),
/// so this panel only mirrors that state read-only. Lives in the Dev View
/// section; compiled out of release builds via the `kDebugMode` guard at its
/// call site.
class _AfterCallDebugPanel extends StatefulWidget {
  const _AfterCallDebugPanel();

  @override
  State<_AfterCallDebugPanel> createState() => _AfterCallDebugPanelState();
}

class _AfterCallDebugPanelState extends State<_AfterCallDebugPanel> {
  // null = not read yet / channel error, so the row never silently goes blank.
  bool? _receiverEnabled;
  bool? _canDrawOverlays;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final enabled = await AfterCallService.isEnabled();
      final canDraw = await LauncherService.canDrawOverlays();
      if (!mounted) return;
      setState(() {
        _receiverEnabled = enabled;
        _canDrawOverlays = canDraw;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  String _statusLabel(bool? value) =>
      value == null ? '—' : (value ? 'YES' : 'no');

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showCardNow() async {
    if (!await LauncherService.canDrawOverlays()) {
      await LauncherService.requestOverlayPermission();
      if (!await LauncherService.canDrawOverlays()) {
        _toast('Overlay permission needed to show the card');
        await _refresh();
        return;
      }
    }
    await AfterCallService.showOverlayNow();
    _toast('Card shown — tap ✕, tap outside, or press Back to close');
    await _refresh();
  }

  Future<void> _setReceiver(bool enabled) async {
    await AfterCallService.setEnabled(enabled);
    _toast(enabled ? 'Call listener installed' : 'Call listener uninstalled');
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'AFTER-CALL TESTER',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            'The card is permission-free: it has no call-log/phone access, so it '
            'shows quick actions only — no caller number or duration.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        if (_error != null)
          ListTile(
            dense: true,
            title: const Text('Channel error'),
            subtitle: Text(_error!),
          ),
        SwitchListTile(
          dense: true,
          title: const Text('Call listener (install / uninstall)'),
          subtitle: Text(
            _receiverEnabled == null
                ? 'Reading…'
                : 'Mirrors the Post-call action center toggle — flip to test',
          ),
          value: _receiverEnabled ?? false,
          onChanged: _receiverEnabled == null ? null : _setReceiver,
        ),
        ListTile(
          dense: true,
          title: const Text('Can draw overlays'),
          trailing: Text(_statusLabel(_canDrawOverlays)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: _showCardNow,
                child: const Text('Show card now'),
              ),
              TextButton(
                onPressed: _refresh,
                child: const Text('Refresh status'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Debug-only controls for previewing install/uninstall assistant overlays.
/// The real feature setting remains under Launcher Features; these buttons live
/// in Dev View because they synthesize package events for visual testing.
class _InstallAssistantDebugPanel extends StatefulWidget {
  const _InstallAssistantDebugPanel();

  @override
  State<_InstallAssistantDebugPanel> createState() =>
      _InstallAssistantDebugPanelState();
}

class _InstallAssistantDebugPanelState
    extends State<_InstallAssistantDebugPanel> {
  bool _busy = false;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showAssistantOverlay({required bool removed}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await LauncherService.canDrawOverlays()) {
        await LauncherService.requestOverlayPermission();
        if (!await LauncherService.canDrawOverlays()) {
          _toast('Overlay permission needed to show the modal');
          return;
        }
      }
      if (!mounted) return;
      final appsCubit = context.read<AppsCubit>();
      var apps = appsCubit.state.apps.where((app) => !app.isInternalFeature);
      if (apps.isEmpty) {
        await appsCubit.loadApps(forceFull: true);
        apps = appsCubit.state.apps.where((app) => !app.isInternalFeature);
      }
      if (apps.isEmpty) {
        _toast('No installed apps available for preview');
        return;
      }
      await InstallAssistantService.showOverlayNow(
        apps.first.packageName,
        removed: removed,
      );
      _toast(removed ? 'Uninstall modal shown' : 'Install modal shown');
    } catch (e) {
      _toast('Could not show assistant modal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'INSTALL ASSISTANT TESTER',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          const Text(
            'Preview the native install/uninstall overlays without changing installed apps.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed:
                    _busy ? null : () => _showAssistantOverlay(removed: false),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Show install modal'),
              ),
              FilledButton.tonalIcon(
                onPressed:
                    _busy ? null : () => _showAssistantOverlay(removed: true),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Show uninstall modal'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Temporary tester for verifying Firebase Crashlytics wiring end-to-end.
///
/// Unlike the other dev panels this is NOT gated behind [kDebugMode], because
/// collection is disabled in debug (`setCrashlyticsCollectionEnabled(!kDebugMode)`
/// in main.dart) — reports only upload from a release build. Exercises all three
/// capture paths:
///   • fatal native crash (`crash()`) → uploads on the *next* app launch,
///   • non-fatal `recordError(..., fatal: false)`,
///   • uncaught async error → caught by the `runZonedGuarded` handler in main().
///
/// Strip this panel (and its list entry/header) before shipping.
class _CrashlyticsDebugPanel extends StatelessWidget {
  const _CrashlyticsDebugPanel();

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CRASHLYTICS TESTER',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          Text(
            kDebugMode
                ? 'Collection is OFF in debug — install a RELEASE build, then '
                    'tap a button below. Forced crashes upload on the next launch.'
                : 'Tap to send a test event to Crashlytics. A forced crash uploads '
                    'on the next app launch; non-fatals upload in the background.',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () {
                  _toast(context,
                      'Recorded non-fatal. Check Crashlytics in a minute or two.');
                  FirebaseCrashlytics.instance.recordError(
                    Exception('Test non-fatal from Settings'),
                    StackTrace.current,
                    reason: 'Crashlytics tester',
                    fatal: false,
                  );
                },
                icon: const Icon(Icons.report_gmailerrorred_outlined),
                label: const Text('Log non-fatal'),
              ),
              FilledButton.tonalIcon(
                onPressed: () {
                  _toast(context, 'Throwing uncaught async error…');
                  // Escapes to the runZonedGuarded handler in main().
                  Future<void>.delayed(
                    const Duration(milliseconds: 150),
                    () => throw Exception('Test uncaught async from Settings'),
                  );
                },
                icon: const Icon(Icons.bolt_outlined),
                label: const Text('Throw async error'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  _toast(context,
                      'Crashing now — REOPEN the app to upload the report.');
                  // Small delay so the toast paints before the native crash.
                  Future<void>.delayed(
                    const Duration(milliseconds: 400),
                    () => FirebaseCrashlytics.instance.crash(),
                  );
                },
                icon: const Icon(Icons.dangerous_outlined),
                label: const Text('Force crash'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Debug-only controls for exercising the native alarm full-screen flow from
/// the main launcher settings instead of the Clock mini-app toolbar.
class _AlarmDebugPanel extends StatefulWidget {
  const _AlarmDebugPanel();

  @override
  State<_AlarmDebugPanel> createState() => _AlarmDebugPanelState();
}

class _AlarmDebugPanelState extends State<_AlarmDebugPanel> {
  bool _busy = false;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _scheduleTestAlarm({
    required bool goodMorning,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await LauncherService.canScheduleExactAlarms()) {
        await LauncherService.requestExactAlarmAccess();
      }
      final notif = await Permission.notification.status;
      if (!notif.isGranted && !notif.isPermanentlyDenied) {
        await Permission.notification.request();
      }
      final trigger = DateTime.now().add(const Duration(seconds: 5));
      final ok = await LauncherService.scheduleSmartAlarm(
        id: goodMorning
            ? ClockRepository.goodMorningTestAlarmId
            : ClockRepository.testAlarmId,
        triggerAtMillis: trigger.millisecondsSinceEpoch,
        label: goodMorning ? 'Good morning test alarm' : 'Test alarm',
        hour: trigger.hour,
        minute: trigger.minute,
        vibrate: true,
        autoSilenceMinutes: 1,
        kind: 'alarm',
      );
      _toast(
        ok
            ? goodMorning
                ? 'Good Morning test rings in 5s — dismiss it to open the dashboard.'
                : 'Test alarm rings in 5s — lock the phone to see the full-screen ring.'
            : 'Could not schedule. Allow exact alarms, then try again.',
      );
    } catch (e) {
      _toast('Could not schedule test alarm: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ALARM TESTER',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          const Text(
            'Schedule throwaway alarms through the real native ring service.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed:
                    _busy ? null : () => _scheduleTestAlarm(goodMorning: false),
                icon: const Icon(Icons.alarm),
                label: const Text('Test alarm'),
              ),
              FilledButton.tonalIcon(
                onPressed:
                    _busy ? null : () => _scheduleTestAlarm(goodMorning: true),
                icon: const Icon(Icons.wb_sunny_outlined),
                label: const Text('Good Morning test'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
