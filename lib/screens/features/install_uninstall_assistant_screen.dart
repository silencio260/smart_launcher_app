import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/launcher_feature_settings.dart';
import '../../services/install_assistant_service.dart';
import '../../services/launcher_service.dart';
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
                onChanged: (value) async {
                  if (value) {
                    // The card is a system overlay drawn over whatever is on
                    // screen when an app is installed/removed, so it needs the
                    // "draw over other apps" grant — not a package permission.
                    if (!await LauncherService.canDrawOverlays()) {
                      await LauncherService.requestOverlayPermission();
                      if (!await LauncherService.canDrawOverlays()) return;
                    }
                  }
                  await InstallAssistantService.setEnabled(value);
                  cubit.update(
                    state.copyWith(installUninstallAssistantEnabled: value),
                  );
                },
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'The assistant card needs the "draw over other apps" '
                  'permission so it can appear on top of the Play Store or '
                  'Settings — wherever you are when an app is added or removed.',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
