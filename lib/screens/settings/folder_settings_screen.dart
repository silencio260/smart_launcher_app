import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/launcher_settings.dart';
import '../../state/settings_cubit.dart';
import 'icon_shape_picker_screen.dart';

class FolderSettingsScreen extends StatelessWidget {
  const FolderSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Folders')),
      body: BlocBuilder<SettingsCubit, LauncherSettings>(
        builder: (context, s) {
          final cubit = context.read<SettingsCubit>();
          return ListView(
            children: [
              _SectionHeader('Appearance'),
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: const Text('Folder Icon Shape'),
                subtitle: Text(s.folderIconShape.replaceAll('_', ' ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final shape = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => IconShapePickerScreen(current: s.folderIconShape),
                    ),
                  );
                  if (shape != null) cubit.update(s.copyWith(folderIconShape: shape));
                },
              ),
              ListTile(
                leading: const Icon(Icons.color_lens_outlined),
                title: const Text('Folder Background Color'),
                trailing: _ColorDot(s.folderColor),
                onTap: () => _pickColor(context, cubit, s),
              ),
              _SectionHeader('Grid'),
              _SliderTile(
                icon: Icons.view_column_outlined,
                title: 'Max Columns',
                value: s.folderMaxColumns.toDouble(),
                min: 2,
                max: 5,
                divisions: 3,
                label: '${s.folderMaxColumns}',
                onChanged: (v) => cubit.update(s.copyWith(folderMaxColumns: v.round())),
              ),
              _SliderTile(
                icon: Icons.table_rows_outlined,
                title: 'Max Rows',
                value: s.folderMaxRows.toDouble(),
                min: 2,
                max: 5,
                divisions: 3,
                label: '${s.folderMaxRows}',
                onChanged: (v) => cubit.update(s.copyWith(folderMaxRows: v.round())),
              ),
              _SectionHeader('Labels'),
              SwitchListTile(
                title: const Text('Show Folder Labels'),
                secondary: const Icon(Icons.label_outline),
                value: s.showFolderLabels,
                onChanged: (v) => cubit.update(s.copyWith(showFolderLabels: v)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _pickColor(BuildContext context, SettingsCubit cubit, LauncherSettings s) {
    final options = <(String, Color)>[
      ('Dark', Colors.black54),
      ('Blue', Colors.blue.shade900),
      ('Purple', Colors.purple.shade900),
      ('Green', Colors.green.shade900),
      ('Red', Colors.red.shade900),
    ];
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Folder Color'),
        children: options
            .map((o) => ListTile(
                  leading: CircleAvatar(backgroundColor: o.$2, radius: 14),
                  title: Text(o.$1),
                  onTap: () {
                    cubit.update(s.copyWith(folderColor: o.$2));
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
