import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/launcher_feature_settings.dart';
import '../../state/launcher_feature_cubit.dart';

class InstallUninstallAssistantScreen extends StatelessWidget {
  const InstallUninstallAssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Install & Uninstall Assistant')),
      body: BlocBuilder<LauncherFeatureSettingsCubit, LauncherFeatureSettings>(
        builder: (context, state) {
          final cubit = context.read<LauncherFeatureSettingsCubit>();
          return ListView(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.system_update_alt_outlined),
                title: const Text('Assistant enabled'),
                subtitle: const Text('React to app installs and removals'),
                value: state.installAssistantEnabled,
                onChanged: (value) => cubit.update(
                  state.copyWith(installAssistantEnabled: value),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.add_to_home_screen_outlined),
                title: const Text('Prompt on new installs'),
                subtitle: const Text('Offer open, add to home, or hide'),
                value: state.promptOnInstall,
                onChanged: state.installAssistantEnabled
                    ? (value) => cubit.update(
                          state.copyWith(promptOnInstall: value),
                        )
                    : null,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.cleaning_services_outlined),
                title: const Text('Clean up removed apps'),
                subtitle:
                    const Text('Remove stale icons from home and folders'),
                value: state.cleanupOnUninstall,
                onChanged: state.installAssistantEnabled
                    ? (value) => cubit.update(
                          state.copyWith(cleanupOnUninstall: value),
                        )
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }
}
