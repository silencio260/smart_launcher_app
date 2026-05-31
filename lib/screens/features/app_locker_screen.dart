import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/mini_app_repositories.dart';
import '../../models/app_info.dart';
import '../../models/launcher_feature.dart';
import '../../models/launcher_feature_settings.dart';
import '../../services/launcher_service.dart';
import '../../state/apps_cubit.dart';
import '../../state/launcher_feature_cubit.dart';
import '../../widgets/icons/shaped_icon.dart';
import 'mini_app_chrome.dart';

class AppLockerScreen extends StatefulWidget {
  const AppLockerScreen({super.key});

  @override
  State<AppLockerScreen> createState() => _AppLockerScreenState();
}

class _AppLockerScreenState extends State<AppLockerScreen> {
  final _policy = MiniAppPolicyRepository();
  var _query = '';
  var _usage = false;
  var _accessibility = false;
  var _overlay = false;

  @override
  void initState() {
    super.initState();
    _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final usage = await LauncherService.isUsageAccessEnabled();
    final accessibility = await LauncherService.isAccessibilityServiceEnabled();
    final overlay = await LauncherService.canDrawOverlays();
    if (!mounted) return;
    setState(() {
      _usage = usage;
      _accessibility = accessibility;
      _overlay = overlay;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MiniAppScaffold(
      title: 'App Locker',
      child: BlocBuilder<AppsCubit, AppsState>(
        builder: (context, appsState) {
          final apps = appsState.apps
              .where((app) => !LauncherFeatureCatalog.isFeatureApp(app))
              .where((app) =>
                  _query.isEmpty ||
                  app.name.toLowerCase().contains(_query.toLowerCase()) ||
                  app.packageName.toLowerCase().contains(_query.toLowerCase()))
              .toList(growable: false);
          return BlocBuilder<LauncherFeatureSettingsCubit,
              LauncherFeatureSettings>(
            builder: (context, featureSettings) {
              final locked = featureSettings.lockedApps.toSet();
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                children: [
                  _buildHeader(locked.length),
                  const SizedBox(height: 14),
                  _buildPermissionStack(),
                  const SizedBox(height: 14),
                  _buildPolicyControls(),
                  const SizedBox(height: 14),
                  TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Search apps',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: miniAppSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
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
    );
  }

  Widget _buildHeader(int lockedCount) {
    final ready = _usage && _accessibility && _overlay;
    return MiniCard(
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: ready ? const Color(0xFF193C23) : const Color(0xFF3C2419),
              shape: BoxShape.circle,
            ),
            child: Icon(
              ready ? Icons.verified_user : Icons.security,
              color: ready ? Colors.greenAccent : miniAppAccent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ready ? 'Device-wide protection active' : 'Protection setup',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '$lockedCount apps locked. Launcher fallback always works.',
                  style: const TextStyle(color: miniAppMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionStack() {
    return Column(
      children: [
        PermissionPill(
          icon: Icons.query_stats,
          label: 'Usage Access',
          value: _usage ? 'On' : 'Needed',
          onTap: () async {
            await LauncherService.requestUsageAccess();
            await _refreshPermissions();
          },
        ),
        const SizedBox(height: 10),
        PermissionPill(
          icon: Icons.accessibility_new,
          label: 'Accessibility Lock Service',
          value: _accessibility ? 'On' : 'Needed',
          onTap: () async {
            await LauncherService.requestAccessibilityAccess();
            await _refreshPermissions();
          },
        ),
        const SizedBox(height: 10),
        PermissionPill(
          icon: Icons.layers_outlined,
          label: 'Lock screen overlay',
          value: _overlay ? 'On' : 'Needed',
          onTap: () async {
            await LauncherService.requestOverlayPermission();
            await _refreshPermissions();
          },
        ),
      ],
    );
  }

  Widget _buildPolicyControls() {
    return MiniCard(
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Lock newly installed apps'),
            subtitle: const Text('Prompt from Install Assistant'),
            value: _policy.lockNewApps,
            onChanged: (value) async {
              await _policy.setLockNewApps(value);
              setState(() {});
            },
          ),
          const Divider(color: miniAppSurface2),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Relock policy'),
            subtitle: Text(_policy.relockPolicy),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final next = _policy.relockPolicy == 'screen_off'
                  ? 'immediately'
                  : 'screen_off';
              await _policy.setRelockPolicy(next);
              setState(() {});
            },
          ),
          const Divider(color: miniAppSurface2),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Intruder attempts'),
            subtitle: Text('${_policy.intruderAttempts().length} captured'),
            trailing: const Icon(Icons.camera_alt_outlined),
          ),
        ],
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
        app.packageName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: miniAppMuted),
      ),
      trailing: Switch(value: locked, onChanged: onChanged),
    );
  }
}
