import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/launcher_feature_settings.dart';
import '../../state/launcher_feature_cubit.dart';

class AfterCallSettingsScreen extends StatelessWidget {
  const AfterCallSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('After Call')),
      body: BlocBuilder<LauncherFeatureSettingsCubit, LauncherFeatureSettings>(
        builder: (context, state) {
          final cubit = context.read<LauncherFeatureSettingsCubit>();
          return ListView(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.call_end_outlined),
                title: const Text('Post-call action center'),
                subtitle: const Text(
                  'Shows quick actions after calls when the launcher is visible',
                ),
                value: state.afterCallEnabled,
                onChanged: (value) async {
                  if (value) {
                    final status = await Permission.phone.request();
                    if (!status.isGranted) return;
                  }
                  cubit.update(state.copyWith(afterCallEnabled: value));
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.layers_outlined),
                title: const Text('Use overlay when available'),
                subtitle: const Text(
                  'Requires the floating menu permission from Launcher Features',
                ),
                value: state.overlayMenusEnabled,
                onChanged: (value) =>
                    cubit.update(state.copyWith(overlayMenusEnabled: value)),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'This version avoids call-log access and does not show caller names or numbers.',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
