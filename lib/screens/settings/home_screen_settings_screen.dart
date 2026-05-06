import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/launcher_settings.dart';
import '../../state/settings_cubit.dart';

class HomeScreenSettingsScreen extends StatelessWidget {
  const HomeScreenSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home Screen')),
      body: BlocBuilder<SettingsCubit, LauncherSettings>(
        builder: (context, s) {
          final cubit = context.read<SettingsCubit>();
          return ListView(
            children: [
              _SectionHeader('Grid'),
              _SliderTile(
                icon: Icons.grid_view,
                title: 'Columns',
                value: s.gridColumns.toDouble(),
                min: 3,
                max: 8,
                divisions: 5,
                label: '${s.gridColumns}',
                onChanged: (v) => cubit.update(s.copyWith(gridColumns: v.round())),
              ),
              _SliderTile(
                icon: Icons.table_rows_outlined,
                title: 'Rows',
                value: s.gridRows.toDouble(),
                min: 3,
                max: 8,
                divisions: 5,
                label: '${s.gridRows}',
                onChanged: (v) => cubit.update(s.copyWith(gridRows: v.round())),
              ),
              _SliderTile(
                icon: Icons.photo_size_select_large_outlined,
                title: 'Icon Size',
                value: s.iconSize,
                min: 36,
                max: 72,
                divisions: 9,
                label: '${s.iconSize.round()}dp',
                onChanged: (v) => cubit.update(s.copyWith(iconSize: v)),
              ),
              _SectionHeader('Labels'),
              SwitchListTile(
                title: const Text('Show Icon Labels'),
                secondary: const Icon(Icons.label_outline),
                value: s.showLabels,
                onChanged: (v) => cubit.update(s.copyWith(showLabels: v)),
              ),
              _SliderTile(
                icon: Icons.format_size,
                title: 'Label Size',
                value: s.labelSize,
                min: 8,
                max: 18,
                divisions: 10,
                label: '${s.labelSize.round()}sp',
                onChanged: s.showLabels
                    ? (v) => cubit.update(s.copyWith(labelSize: v))
                    : null,
              ),
              _SectionHeader('Behavior'),
              SwitchListTile(
                title: const Text('Lock Home Screen'),
                subtitle: const Text('Prevent icon rearrangement'),
                secondary: const Icon(Icons.lock_outlined),
                value: s.lockHomeScreen,
                onChanged: (v) => cubit.update(s.copyWith(lockHomeScreen: v)),
              ),
              SwitchListTile(
                title: const Text('Auto-add Shortcuts'),
                subtitle: const Text('Add new app icons automatically'),
                secondary: const Icon(Icons.add_circle_outline),
                value: s.autoAddShortcuts,
                onChanged: (v) => cubit.update(s.copyWith(autoAddShortcuts: v)),
              ),
              SwitchListTile(
                title: const Text('Infinite Scrolling'),
                secondary: const Icon(Icons.all_inclusive),
                value: s.infiniteScrolling,
                onChanged: (v) => cubit.update(s.copyWith(infiniteScrolling: v)),
              ),
              _SectionHeader('Status Bar'),
              SwitchListTile(
                title: const Text('Show Status Bar'),
                secondary: const Icon(Icons.signal_cellular_alt),
                value: s.showStatusBar,
                onChanged: (v) => cubit.update(s.copyWith(showStatusBar: v)),
              ),
              SwitchListTile(
                title: const Text('Dark Status Bar Icons'),
                secondary: const Icon(Icons.invert_colors),
                value: s.darkStatusBar,
                onChanged: s.showStatusBar
                    ? (v) => cubit.update(s.copyWith(darkStatusBar: v))
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.text_format),
                title: const Text('Text Color Mode'),
                subtitle: Text(_textColorLabel(s.textColorMode)),
                onTap: () => _pickTextColor(context, cubit, s),
              ),
              _SectionHeader('Wallpaper'),
              SwitchListTile(
                title: const Text('Wallpaper Scrolling'),
                subtitle: const Text('Parallax effect on page swipe'),
                secondary: const Icon(Icons.panorama_outlined),
                value: s.wallpaperScrolling,
                onChanged: (v) => cubit.update(s.copyWith(wallpaperScrolling: v)),
              ),
              SwitchListTile(
                title: const Text('Depth Effect'),
                secondary: const Icon(Icons.layers_outlined),
                value: s.wallpaperDepthEffect,
                onChanged: (v) => cubit.update(s.copyWith(wallpaperDepthEffect: v)),
              ),
              SwitchListTile(
                title: const Text('Blur Wallpaper'),
                secondary: const Icon(Icons.blur_on),
                value: s.wallpaperBlur,
                onChanged: (v) => cubit.update(s.copyWith(wallpaperBlur: v)),
              ),
              _SliderTile(
                icon: Icons.blur_linear,
                title: 'Blur Intensity',
                value: s.wallpaperBlurIntensity,
                min: 0.1,
                max: 1.0,
                divisions: 9,
                label: '${(s.wallpaperBlurIntensity * 100).round()}%',
                onChanged: s.wallpaperBlur
                    ? (v) => cubit.update(s.copyWith(wallpaperBlurIntensity: v))
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }

  String _textColorLabel(TextColorMode m) => switch (m) {
        TextColorMode.auto => 'Auto (white with shadow)',
        TextColorMode.light => 'Light',
        TextColorMode.dark => 'Dark',
      };

  void _pickTextColor(BuildContext context, SettingsCubit cubit, LauncherSettings s) {
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Text Color Mode'),
        children: TextColorMode.values
            .map((m) => RadioListTile<TextColorMode>(
                  title: Text(_textColorLabel(m)),
                  value: m,
                  groupValue: s.textColorMode,
                  onChanged: (v) {
                    if (v != null) cubit.update(s.copyWith(textColorMode: v));
                    Navigator.pop(context);
                  },
                ))
            .toList(),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double>? onChanged;

  const _SliderTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
      ),
      trailing: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
