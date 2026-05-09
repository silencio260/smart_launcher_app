import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/launcher_settings.dart';
import '../../state/apps_cubit.dart';
import '../../state/settings_cubit.dart';
import 'hidden_apps_screen.dart';

class DrawerSettingsScreen extends StatelessWidget {
  const DrawerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Drawer')),
      body: BlocBuilder<SettingsCubit, LauncherSettings>(
        builder: (context, s) {
          final cubit = context.read<SettingsCubit>();
          return ListView(
            children: [
              _SectionHeader('Layout'),
              ListTile(
                leading: const Icon(Icons.view_module_outlined),
                title: const Text('Layout'),
                subtitle: Text(s.drawerLayout == DrawerLayout.standard ? 'Standard (A–Z)' : 'Caddy (by category)'),
                onTap: () => _pickLayout(context, cubit, s),
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Hidden Apps'),
                subtitle: Text('${s.hiddenApps.length} hidden'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BlocProvider.value(
                      value: context.read<AppsCubit>(),
                      child: const HiddenAppsScreen(),
                    ),
                  ),
                ),
              ),
              _SectionHeader('Appearance'),
              SwitchListTile(
                title: const Text('Background Color'),
                subtitle: const Text('Tint behind the app list'),
                secondary: const Icon(Icons.color_lens_outlined),
                value: s.drawerShowBackground,
                onChanged: (v) => cubit.update(s.copyWith(drawerShowBackground: v)),
              ),
              if (s.drawerShowBackground) ...[
                ListTile(
                  leading: const Icon(Icons.circle_outlined),
                  title: const Text('Color'),
                  trailing: _ColorDot(s.drawerBackgroundColor),
                  onTap: () => _pickColor(context, cubit, s),
                ),
                _SliderTile(
                  icon: Icons.opacity,
                  title: 'Opacity',
                  value: s.drawerBackgroundOpacity,
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  label: '${(s.drawerBackgroundOpacity * 100).round()}%',
                  onChanged: (v) => cubit.update(s.copyWith(drawerBackgroundOpacity: v)),
                ),
              ],
              _SectionHeader('Grid'),
              _SliderTile(
                icon: Icons.view_column_outlined,
                title: 'Columns',
                value: s.drawerColumns.toDouble(),
                min: 3,
                max: 6,
                divisions: 3,
                label: '${s.drawerColumns}',
                onChanged: (v) => cubit.update(s.copyWith(drawerColumns: v.round())),
              ),
              _SliderTile(
                icon: Icons.photo_size_select_large_outlined,
                title: 'Icon Size',
                value: s.drawerIconSize,
                min: 36,
                max: 72,
                divisions: 9,
                label: '${s.drawerIconSize.round()}dp',
                onChanged: (v) => cubit.update(s.copyWith(drawerIconSize: v)),
              ),
              _SectionHeader('Labels'),
              SwitchListTile(
                title: const Text('Show Labels'),
                secondary: const Icon(Icons.label_outline),
                value: s.showDrawerLabels,
                onChanged: (v) => cubit.update(s.copyWith(showDrawerLabels: v)),
              ),
              _SectionHeader('Scroll'),
              SwitchListTile(
                title: const Text('Remember Scroll Position'),
                secondary: const Icon(Icons.bookmark_outline),
                value: s.drawerRememberScroll,
                onChanged: (v) => cubit.update(s.copyWith(drawerRememberScroll: v)),
              ),
              SwitchListTile(
                title: const Text('Show Scrollbar'),
                secondary: const Icon(Icons.linear_scale),
                value: s.drawerShowScrollbar,
                onChanged: (v) => cubit.update(s.copyWith(drawerShowScrollbar: v)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _pickLayout(BuildContext context, SettingsCubit cubit, LauncherSettings s) {
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Layout'),
        children: [
          RadioListTile<DrawerLayout>(
            title: const Text('Standard (A–Z)'),
            subtitle: const Text('Alphabetical with section headers'),
            value: DrawerLayout.standard,
            groupValue: s.drawerLayout,
            onChanged: (v) {
              if (v != null) cubit.update(s.copyWith(drawerLayout: v));
              Navigator.pop(context);
            },
          ),
          RadioListTile<DrawerLayout>(
            title: const Text('Caddy (by category)'),
            subtitle: const Text('Grouped by app category'),
            value: DrawerLayout.caddy,
            groupValue: s.drawerLayout,
            onChanged: (v) {
              if (v != null) cubit.update(s.copyWith(drawerLayout: v));
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _pickColor(BuildContext context, SettingsCubit cubit, LauncherSettings s) {
    final colors = [Colors.black, Colors.grey.shade900, Colors.blueGrey.shade900];
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Background Color'),
        children: colors
            .map((c) => ListTile(
                  leading: CircleAvatar(backgroundColor: c, radius: 14),
                  title: Text(c == Colors.black ? 'Black' : 'Dark ${colors.indexOf(c)}'),
                  onTap: () {
                    cubit.update(s.copyWith(drawerBackgroundColor: c));
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

class _ColorDot extends StatelessWidget {
  final Color color;
  const _ColorDot(this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade400),
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
