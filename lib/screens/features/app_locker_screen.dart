import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/app_info.dart';
import '../../models/launcher_feature.dart';
import '../../models/launcher_feature_settings.dart';
import '../../services/launcher_service.dart';
import '../../state/apps_cubit.dart';
import '../../state/launcher_feature_cubit.dart';
import '../../widgets/icons/shaped_icon.dart';
import 'clock/clock_theme.dart';
import 'mini_app_chrome.dart';
import 'mini_app_kit.dart';

class AppLockerScreen extends StatefulWidget {
  const AppLockerScreen({super.key});

  @override
  State<AppLockerScreen> createState() => _AppLockerScreenState();
}

class _AppLockerScreenState extends State<AppLockerScreen> {
  var _query = '';
  var _accessibility = false;
  var _overlay = false;

  @override
  void initState() {
    super.initState();
    _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final accessibility = await LauncherService.isAccessibilityServiceEnabled();
    final overlay = await LauncherService.canDrawOverlays();
    if (!mounted) return;
    setState(() {
      _accessibility = accessibility;
      _overlay = overlay;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MiniAppScaffold(
      title: 'App Locker',
      child: Theme(
        data: clockThemeOf(context),
        child: BlocBuilder<AppsCubit, AppsState>(
          builder: (context, appsState) {
            final apps = appsState.apps
                .where((app) => !LauncherFeatureCatalog.isFeatureApp(app))
                .where((app) =>
                    _query.isEmpty ||
                    app.name.toLowerCase().contains(_query.toLowerCase()) ||
                    app.packageName
                        .toLowerCase()
                        .contains(_query.toLowerCase()))
                .toList(growable: false);
            return BlocBuilder<LauncherFeatureSettingsCubit,
                LauncherFeatureSettings>(
              builder: (context, featureSettings) {
                final locked = featureSettings.lockedApps.toSet();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                  children: [
                    _statusCard(locked.length),
                    const SizedBox(height: 12),
                    ..._setupRows(),
                    _searchField(),
                    const SizedBox(height: 6),
                    for (final app in apps)
                      _AppLockTile(
                        app: app,
                        locked: locked.contains(app.packageName),
                        onChanged: (value) => context
                            .read<LauncherFeatureSettingsCubit>()
                            .setAppLocked(app.packageName, value),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _statusCard(int lockedCount) {
    final ready = _accessibility && _overlay;
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
            child: Icon(
              ready ? Icons.lock : Icons.lock_open,
              color: clockAccent,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ready ? 'App Lock is active' : 'Set up App Lock',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ready
                      ? '$lockedCount app${lockedCount == 1 ? '' : 's'} locked behind your device unlock.'
                      : 'Enable the steps below to lock apps device-wide.',
                  style: const TextStyle(color: miniAppMuted, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Only the setup steps that still need granting are shown, so the screen
  /// collapses to the status card + app list once everything is ready.
  List<Widget> _setupRows() {
    final rows = <Widget>[];
    if (!_accessibility) {
      rows.add(_setupRow(
        icon: Icons.accessibility_new,
        title: 'Enable App Lock service',
        subtitle: 'Lets the lock screen appear when you open a locked app',
        onTap: () async {
          await LauncherService.requestAccessibilityAccess();
          await _refreshPermissions();
        },
      ));
    }
    if (!_overlay) {
      rows.add(_setupRow(
        icon: Icons.layers_outlined,
        title: 'Allow display over apps',
        subtitle: 'Lets the unlock prompt show on top of locked apps',
        onTap: () async {
          await LauncherService.requestOverlayPermission();
          await _refreshPermissions();
        },
      ));
    }
    return rows;
  }

  Widget _setupRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MiniFeatureRow(
        icon: icon,
        iconColor: clockAccent,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        trailing: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enable',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            SizedBox(width: 6),
            Icon(Icons.chevron_right, color: miniAppMuted),
          ],
        ),
      ),
    );
  }

  Widget _searchField() {
    return TextField(
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
