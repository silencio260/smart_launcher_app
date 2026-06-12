import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';

class DockSettingsScreen extends StatelessWidget {
  const DockSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dock')),
      body: BlocBuilder<SettingsCubit, LauncherSettings>(
        builder: (context, s) {
          final cubit = context.read<SettingsCubit>();
          final dockSlots = s.dockSize.clamp(3, s.gridColumns).toInt();
          return ListView(
            children: [
              SwitchListTile(
                title: const Text('Show Dock'),
                secondary: const Icon(Icons.dock),
                value: s.showDock,
                onChanged: (v) => cubit.update(s.copyWith(showDock: v)),
              ),
              _SectionHeader('Size'),
              _SliderTile(
                icon: Icons.apps,
                title: 'Dock Slots',
                value: dockSlots.toDouble(),
                min: 3,
                max: s.gridColumns.toDouble(),
                divisions: (s.gridColumns - 3).clamp(1, 4).toInt(),
                label: '$dockSlots',
                onChanged: s.showDock && s.gridColumns > 3
                    ? (v) => cubit.update(s.copyWith(dockSize: v.round()))
                    : null,
              ),
              _SectionHeader('Background'),
              SwitchListTile(
                title: const Text('Show Background'),
                secondary: const Icon(Icons.rectangle_outlined),
                value: s.dockShowBackground,
                onChanged: s.showDock
                    ? (v) => cubit.update(s.copyWith(dockShowBackground: v))
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.color_lens_outlined),
                title: const Text('Background Color'),
                trailing: _ColorDot(s.dockBackgroundColor),
                enabled: s.showDock && s.dockShowBackground,
                onTap: () => _pickColor(context, cubit, s),
              ),
              _SliderTile(
                icon: Icons.opacity,
                title: 'Opacity',
                value: s.dockBackgroundOpacity,
                min: 0.1,
                max: 1.0,
                divisions: 9,
                label: '${(s.dockBackgroundOpacity * 100).round()}%',
                onChanged: (s.showDock && s.dockShowBackground)
                    ? (v) => cubit.update(s.copyWith(dockBackgroundOpacity: v))
                    : null,
              ),
              _SectionHeader('Labels'),
              SwitchListTile(
                title: const Text('Show Labels'),
                secondary: const Icon(Icons.label_outline),
                value: s.showDockLabels,
                onChanged: s.showDock
                    ? (v) => cubit.update(s.copyWith(showDockLabels: v))
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }

  void _pickColor(
      BuildContext context, SettingsCubit cubit, LauncherSettings s) {
    final colors = [
      Colors.black,
      Colors.white,
      Colors.grey.shade900,
      Colors.blueGrey.shade900,
      Colors.grey.shade800,
    ];
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Background Color'),
        children: colors
            .map((c) => ListTile(
                  leading: CircleAvatar(backgroundColor: c, radius: 14),
                  title: Text(c == Colors.black
                      ? 'Black'
                      : c == Colors.white
                          ? 'White'
                          : 'Dark ${colors.indexOf(c)}'),
                  onTap: () {
                    cubit.update(s.copyWith(dockBackgroundColor: c));
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
