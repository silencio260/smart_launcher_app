import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/launcher_settings.dart';
import '../../state/settings_cubit.dart';

class LauncherThemesScreen extends StatelessWidget {
  const LauncherThemesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Themes')),
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
                onTap: () => cubit.update(
                  settings.copyWith(homeMode: HomeMode.smart),
                ),
              ),
              const SizedBox(height: 12),
              _ThemeCard(
                title: 'iOS',
                subtitle: 'Paged icon grid, dock, library, Spotlight',
                icon: Icons.phone_iphone_rounded,
                selected: settings.homeMode == HomeMode.ios,
                onTap: () => cubit.update(
                  settings.copyWith(homeMode: HomeMode.ios),
                ),
              ),
              const SizedBox(height: 12),
              _ThemeCard(
                title: 'Minimal',
                subtitle: 'Clock, date, day progress, favorite apps',
                icon: Icons.format_align_left_rounded,
                selected: settings.homeMode == HomeMode.minimal,
                onTap: () => cubit.update(
                  settings.copyWith(homeMode: HomeMode.minimal),
                ),
              ),
              const SizedBox(height: 24),
              _IosOptions(settings: settings, cubit: cubit),
              const SizedBox(height: 16),
              _MinimalOptions(settings: settings, cubit: cubit),
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
  final VoidCallback onTap;

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
        SwitchListTile(
          secondary: const Icon(Icons.wallpaper_outlined),
          title: const Text('Use wallpaper'),
          subtitle: const Text('Show the device wallpaper, or a solid colour'),
          value: settings.minimalUseWallpaper,
          onChanged: (value) => cubit.update(
            settings.copyWith(minimalUseWallpaper: value),
          ),
        ),
        if (!settings.minimalUseWallpaper)
          _MinimalColorPicker(settings: settings, cubit: cubit),
        SwitchListTile(
          secondary: const Icon(Icons.schedule_outlined),
          title: const Text('24-hour clock'),
          value: settings.minimalUse24HourClock,
          onChanged: (value) => cubit.update(
            settings.copyWith(minimalUse24HourClock: value),
          ),
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
            onChanged: (value) => cubit.update(
              settings.copyWith(minimalFontSize: value),
            ),
          ),
          trailing: Text('${settings.minimalFontSize.round()}'),
        ),
      ],
    );
  }
}

class _MinimalColorPicker extends StatelessWidget {
  final LauncherSettings settings;
  final SettingsCubit cubit;

  const _MinimalColorPicker({required this.settings, required this.cubit});

  static const _swatches = <int>[
    0xFF000000, // black
    0xFF101414, // charcoal (default)
    0xFF1B2430, // navy
    0xFF20161B, // wine
    0xFF14201A, // forest
    0xFF2A2A2E, // graphite
    0xFFF5F5F5, // light
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.palette_outlined),
          const SizedBox(width: 16),
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in _swatches)
                  _ColorSwatch(
                    color: Color(color),
                    selected: settings.minimalBackgroundColor == color,
                    onTap: () => cubit.update(
                      settings.copyWith(minimalBackgroundColor: color),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check,
                size: 16,
                color: color.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
              )
            : null,
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
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
