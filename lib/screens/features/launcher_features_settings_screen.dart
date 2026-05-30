import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/launcher_feature_settings.dart';
import '../../services/launcher_service.dart';
import '../../state/launcher_feature_cubit.dart';
import 'after_call_settings_screen.dart';
import 'install_uninstall_assistant_screen.dart';

class LauncherFeaturesSettingsScreen extends StatelessWidget {
  const LauncherFeaturesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Launcher Features')),
      body: BlocBuilder<LauncherFeatureSettingsCubit, LauncherFeatureSettings>(
        builder: (context, state) {
          final cubit = context.read<LauncherFeatureSettingsCubit>();
          return ListView(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.layers_outlined),
                title: const Text('Show floating menus over other apps'),
                subtitle: const Text('Optional advanced mode for overlays'),
                value: state.overlayMenusEnabled,
                onChanged: (enabled) async {
                  if (enabled) {
                    final granted = await LauncherService.canDrawOverlays();
                    if (!granted) {
                      await LauncherService.requestOverlayPermission();
                    }
                  }
                  cubit.update(state.copyWith(overlayMenusEnabled: enabled));
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.call_end_outlined),
                title: const Text('After Call'),
                subtitle: Text(state.afterCallEnabled ? 'Enabled' : 'Off'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AfterCallSettingsScreen(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.system_update_alt_outlined),
                title: const Text('Install & Uninstall Assistant'),
                subtitle:
                    Text(state.installAssistantEnabled ? 'Enabled' : 'Off'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const InstallUninstallAssistantScreen(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
