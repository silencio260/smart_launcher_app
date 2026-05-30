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
                title: const Text('Install & Uninstall Assistant'),
                subtitle: const Text(
                  'Prompt where to place new apps and clean up icons of '
                  'removed apps',
                ),
                value: state.installUninstallAssistantEnabled,
                onChanged: (value) => cubit.update(
                  state.copyWith(installUninstallAssistantEnabled: value),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
