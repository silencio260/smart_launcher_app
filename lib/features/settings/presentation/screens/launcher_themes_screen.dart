import 'dart:async';
import 'package:flutter/material.dart';
import 'package:smart_launcher_app/core/ads/launcher_ads.dart';
import 'package:smart_launcher_app/core/ads/launcher_banner_ad.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/home_background_sheet.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/settings_appearance.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/wallpaper_screen.dart';

class LauncherThemesScreen extends StatefulWidget {
  const LauncherThemesScreen({super.key});

  @override
  State<LauncherThemesScreen> createState() => _LauncherThemesScreenState();
}

class _LauncherThemesScreenState extends State<LauncherThemesScreen> {
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    unawaited(LauncherAds.preloadAction(LauncherAdPlacements.themeApplied));
  }

  Future<void> _apply(HomeMode mode) async {
    final cubit = context.read<SettingsCubit>();
    if (_applying || cubit.state.homeMode == mode) return;
    setState(() => _applying = true);
    try {
      await cubit.update(cubit.state.copyWith(homeMode: mode));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Theme applied')));
      await LauncherAds.onActionCompleted(
        context,
        LauncherAdPlacements.themeApplied,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save theme. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Themes')),
      bottomNavigationBar: const LauncherBannerAd(
        placement: LauncherAdPlacements.themesBanner,
        showLabel: true,
      ),
      body: BlocBuilder<SettingsCubit, LauncherSettings>(
        builder: (context, settings) {
          final cubit = context.read<SettingsCubit>();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _ThemeCard(
                title: 'Smart',
                subtitle: 'Classic workspace, widgets, dock, drawer',
                icon: Icons.grid_view_rounded,
                selected: settings.homeMode == HomeMode.smart,
                onTap: _applying ? null : () => _apply(HomeMode.smart),
              ),
              const SizedBox(height: 12),
              _ThemeCard(
                title: 'iOS',
                subtitle: 'Paged icon grid, dock, library, Spotlight',
                icon: Icons.phone_iphone_rounded,
                selected: settings.homeMode == HomeMode.ios,
                onTap: _applying ? null : () => _apply(HomeMode.ios),
              ),
              const SizedBox(height: 12),
              _ThemeCard(
                title: 'Minimal',
                subtitle: 'Clock, date, day progress, favorite apps',
                icon: Icons.format_align_left_rounded,
                selected: settings.homeMode == HomeMode.minimal,
                onTap: _applying ? null : () => _apply(HomeMode.minimal),
              ),
              if (settings.homeMode == HomeMode.ios) ...[
                const SizedBox(height: 24),
                _IosOptions(settings: settings, cubit: cubit),
              ],
              if (settings.homeMode == HomeMode.minimal) ...[
                const SizedBox(height: 24),
                _MinimalOptions(settings: settings, cubit: cubit),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  const _ThemeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.52)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 32, color: selected ? scheme.primary : null),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? scheme.primary : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IosOptions extends StatelessWidget {
  final LauncherSettings settings;
  final SettingsCubit cubit;

  const _IosOptions({required this.settings, required this.cubit});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'iOS options',
      children: [
        _BackgroundTile(style: HomeMode.ios, mode: settings.iosBackground),
        ListTile(
          leading: const Icon(Icons.view_column_outlined),
          title: const Text('Grid columns'),
          trailing: DropdownButton<int>(
            value: settings.iosGridColumns.clamp(3, 5).toInt(),
            items: const [3, 4, 5]
                .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              cubit.update(settings.copyWith(iosGridColumns: value));
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.apps_outlined),
          title: const Text('App Library view'),
          trailing: DropdownButton<IosLibraryViewMode>(
            value: settings.iosLibraryViewMode,
            items: const [
              DropdownMenuItem(
                value: IosLibraryViewMode.grid,
                child: Text('Grid'),
              ),
              DropdownMenuItem(
                value: IosLibraryViewMode.list,
                child: Text('List'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              cubit.update(settings.copyWith(iosLibraryViewMode: value));
            },
          ),
        ),
      ],
    );
  }
}

class _MinimalOptions extends StatelessWidget {
  final LauncherSettings settings;
  final SettingsCubit cubit;

  const _MinimalOptions({required this.settings, required this.cubit});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Minimal options',
      children: [
        _BackgroundTile(
          style: HomeMode.minimal,
          mode: settings.minimalBackground,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.schedule_outlined),
          title: const Text('24-hour clock'),
          value: settings.minimalUse24HourClock,
          onChanged: (value) =>
              cubit.update(settings.copyWith(minimalUse24HourClock: value)),
        ),
        ListTile(
          leading: const Icon(Icons.format_size),
          title: const Text('Text size'),
          subtitle: Slider(
            value: settings.minimalFontSize,
            min: 13,
            max: 22,
            divisions: 9,
            label: settings.minimalFontSize.round().toString(),
            onChanged: (value) =>
                cubit.update(settings.copyWith(minimalFontSize: value)),
          ),
          trailing: Text('${settings.minimalFontSize.round()}'),
        ),
      ],
    );
  }
}

class _BackgroundTile extends StatelessWidget {
  final HomeMode style;
  final HomeBackground mode;

  const _BackgroundTile({required this.style, required this.mode});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.wallpaper_outlined),
      title: const Text('Background'),
      subtitle: Text(switch (mode) {
        HomeBackground.wallpaper => 'Phone wallpaper',
        HomeBackground.photo => 'Photo',
        HomeBackground.color => 'Solid colour',
      }),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showHomeBackgroundSheet(
        context,
        style: style,
        onOpenWallpaperBrowser: () {
          final cubit = context.read<SettingsCubit>();
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => BlocProvider.value(
                value: cubit,
                child: const SettingsAppearance(child: WallpaperScreen()),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          ...children,
        ],
      ),
    );
  }
}
