import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/mini_app_repositories.dart';
import '../../models/app_info.dart';
import '../../models/launcher_feature.dart';
import '../../services/launcher_service.dart';
import '../../state/apps_cubit.dart';
import '../../state/settings_cubit.dart';
import '../../widgets/icons/shaped_icon.dart';
import 'mini_app_chrome.dart';
import 'mini_app_kit.dart';

const _featureId = 'app_hider';

class AppHiderScreen extends StatefulWidget {
  const AppHiderScreen({super.key});

  @override
  State<AppHiderScreen> createState() => _AppHiderScreenState();
}

class _AppHiderScreenState extends State<AppHiderScreen> {
  final _policy = MiniAppPolicyRepository();
  var _unlocked = false;
  var _query = '';

  Color get _accent => accentForFeature(_featureId);

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
      child: Theme(
        data: miniAppThemeOf(context, _accent),
        child: !_unlocked
            ? const Center(child: CircularProgressIndicator())
            : BlocBuilder<AppsCubit, AppsState>(
                builder: (context, appsState) {
                  return BlocBuilder<SettingsCubit, dynamic>(
                    builder: (context, settings) {
                      final hidden = settings.hiddenApps.toSet();
                      final visibleApps = appsState.apps
                          .where((app) =>
                              !LauncherFeatureCatalog.isFeatureApp(app))
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
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                        children: [
                          MiniHeroCard(
                            featureId: _featureId,
                            title: 'Hidden Space',
                            subtitle:
                                '${hidden.length} app${hidden.length == 1 ? '' : 's'} invisible from drawer and search.',
                          ),
                          const SizedBox(height: 18),
                          const MiniSectionHeader('Disguise icon'),
                          _buildDisguiseCard(),
                          const SizedBox(height: 18),
                          const MiniSectionHeader('Hide apps'),
                          _searchField(),
                          const SizedBox(height: 6),
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
      ),
    );
  }

  Widget _buildDisguiseCard() {
    final disguise = _policy.disguise;
    return RoundCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pick how this app appears on the home screen. The disguise is '
            'staged through Android aliases.',
            style: TextStyle(color: miniAppMuted, height: 1.3),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final option in const [
                'App Hider',
                'Calculator',
                'Notes',
                'Weather',
                'Browser',
              ])
                _DisguiseChip(
                  label: option,
                  selected: disguise == option,
                  accent: _accent,
                  onTap: () async {
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

class _DisguiseChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _DisguiseChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent : miniAppSurface2,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
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
