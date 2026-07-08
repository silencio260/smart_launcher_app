import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:smart_launcher_app/features/home/presentation/bloc/workspace_cubit.dart';

class BackupRestoreScreen extends StatelessWidget {
  const BackupRestoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Export your launcher layout and settings to a file, '
              'or import a previously exported backup.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Export Backup'),
            subtitle: const Text('Temporarily disabled'),
            enabled: false,
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Import Backup'),
            subtitle: const Text('Temporarily disabled'),
            enabled: false,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.restore, color: Colors.red),
            title: const Text('Reset to Defaults',
                style: TextStyle(color: Colors.red)),
            subtitle: const Text('Clear all settings and layout'),
            onTap: () => _confirmReset(context),
          ),
        ],
      ),
    );
  }

  void _confirmReset(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: const Text(
          'This will clear all your settings and home screen layout. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              context.read<SettingsCubit>().reset();
              context.read<WorkspaceCubit>().loadLayout();
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}
