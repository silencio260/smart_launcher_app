import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/mini_app_repositories.dart';
import '../../models/app_info.dart';
import '../../models/launcher_feature.dart';
import '../../services/launcher_service.dart';
import '../../state/apps_cubit.dart';
import '../../state/settings_cubit.dart';
import '../../widgets/icons/feature_icon.dart';
import '../../widgets/icons/shaped_icon.dart';
import 'mini_app_chrome.dart';

class AppHiderScreen extends StatefulWidget {
  const AppHiderScreen({super.key});

  @override
  State<AppHiderScreen> createState() => _AppHiderScreenState();
}

class _AppHiderScreenState extends State<AppHiderScreen> {
  final _policy = MiniAppPolicyRepository();
  var _unlocked = false;
  var _query = '';

  @override
  void initState() {
    super.initState();
    _unlock();
  }

  Future<void> _unlock() async {
    final ok = await LauncherService.authenticateDevice(
      title: 'Unlock Hidden Space',
      description: 'Confirm before viewing hidden apps',
    );
    if (!mounted) return;
    if (!ok) {
      Navigator.pop(context);
      return;
    }
    setState(() => _unlocked = true);
  }

  @override
  Widget build(BuildContext context) {
    return MiniAppScaffold(
      title: 'App Hider',
      child: !_unlocked
          ? const Center(child: CircularProgressIndicator())
          : BlocBuilder<AppsCubit, AppsState>(
              builder: (context, appsState) {
                return BlocBuilder<SettingsCubit, dynamic>(
                  builder: (context, settings) {
                    final hidden = settings.hiddenApps.toSet();
                    final visibleApps = appsState.apps
                        .where(
                            (app) => !LauncherFeatureCatalog.isFeatureApp(app))
                        .where((app) =>
                            _query.isEmpty ||
                            app.name
                                .toLowerCase()
                                .contains(_query.toLowerCase()) ||
                            app.packageName
                                .toLowerCase()
                                .contains(_query.toLowerCase()))
                        .toList(growable: false);
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                      children: [
                        _buildHeader(hidden.length),
                        const SizedBox(height: 14),
                        _buildDisguiseCard(),
                        const SizedBox(height: 14),
                        TextField(
                          onChanged: (value) => setState(() => _query = value),
                          decoration: InputDecoration(
                            hintText: 'Search apps to hide',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: miniAppSurface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final app in visibleApps)
                          _HiddenSpaceTile(
                            app: app,
                            hidden: hidden.contains(app.launcherKey) ||
                                hidden.contains(app.packageName),
                            onChanged: (value) => _setHidden(app, value),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildHeader(int hiddenCount) {
    return MiniCard(
      child: Row(
        children: [
          const FeatureIcon(featureId: 'app_hider', size: 58),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Hidden Space',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  '$hiddenCount entries invisible from drawer and search',
                  style: const TextStyle(color: miniAppMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisguiseCard() {
    final disguise = _policy.disguise;
    return MiniCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Disguise icon',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 8),
          const Text(
            'Calculator disguise is staged through Android aliases. The current visible name is stored in Hive.',
            style: TextStyle(color: miniAppMuted),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: [
              for (final option in const [
                'App Hider',
                'Calculator',
                'Notes',
                'Weather',
                'Browser',
              ])
                ChoiceChip(
                  label: Text(option),
                  selected: disguise == option,
                  onSelected: (_) async {
                    await _policy.setDisguise(option);
                    await LauncherService.setAppHiderDisguise(option);
                    setState(() {});
                  },
                ),
            ],
          ),
        ],
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
