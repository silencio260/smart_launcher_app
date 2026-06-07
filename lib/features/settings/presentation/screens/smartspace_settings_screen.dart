import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';

class SmartspaceSettingsScreen extends StatelessWidget {
  const SmartspaceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smartspace')),
      body: BlocBuilder<SettingsCubit, LauncherSettings>(
        builder: (context, s) {
          final cubit = context.read<SettingsCubit>();
          return ListView(
            children: [
              _SectionHeader('Clock'),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('Time Format'),
                subtitle: Text(s.timeFormat == TimeFormat.h12
                    ? '12-hour (1:30 PM)'
                    : '24-hour (13:30)'),
                onTap: () => _pickTimeFormat(context, cubit, s),
              ),
              ListTile(
                leading: const Icon(Icons.font_download_outlined),
                title: const Text('Font'),
                subtitle: Text(s.workspaceFont.isEmpty
                    ? 'System default'
                    : s.workspaceFont),
                onTap: () => _pickFont(context, cubit, s),
              ),
              _SectionHeader('Cards'),
              const ListTile(
                leading: Icon(Icons.event_outlined),
                title: Text('Calendar Events'),
                subtitle: Text('Shows upcoming events within 30 minutes'),
                trailing: Icon(Icons.check, color: Colors.green),
              ),
              const ListTile(
                leading: Icon(Icons.alarm),
                title: Text('Next Alarm'),
                subtitle: Text('Shows upcoming alarm time'),
                trailing: Icon(Icons.check, color: Colors.green),
              ),
            ],
          );
        },
      ),
    );
  }

  void _pickTimeFormat(
      BuildContext context, SettingsCubit cubit, LauncherSettings s) {
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Time Format'),
        children: [
          RadioListTile<TimeFormat>(
            title: const Text('12-hour (1:30 PM)'),
            value: TimeFormat.h12,
            groupValue: s.timeFormat,
            onChanged: (v) {
              if (v != null) cubit.update(s.copyWith(timeFormat: v));
              Navigator.pop(context);
            },
          ),
          RadioListTile<TimeFormat>(
            title: const Text('24-hour (13:30)'),
            value: TimeFormat.h24,
            groupValue: s.timeFormat,
            onChanged: (v) {
              if (v != null) cubit.update(s.copyWith(timeFormat: v));
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _pickFont(
      BuildContext context, SettingsCubit cubit, LauncherSettings s) {
    final fonts = ['', 'Roboto', 'Montserrat', 'Lato', 'Nunito', 'Poppins'];
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Font'),
        children: fonts
            .map((f) => RadioListTile<String>(
                  title: Text(f.isEmpty ? 'System default' : f),
                  value: f,
                  groupValue: s.workspaceFont,
                  onChanged: (v) {
                    if (v != null) cubit.update(s.copyWith(workspaceFont: v));
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
