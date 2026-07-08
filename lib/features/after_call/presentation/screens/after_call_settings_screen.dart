import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smart_launcher_app/core/models/launcher_feature_settings.dart';
import 'package:smart_launcher_app/features/after_call/data/after_call_service.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/launcher_feature_cubit.dart';

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
                  'Shows quick actions over the screen right after a call ends',
                ),
                value: state.afterCallEnabled,
                onChanged: (value) async {
                  if (value) {
                    // The card is a system overlay drawn over the dialer, so it
                    // needs the "draw over other apps" grant — NOT a phone
                    // permission. Detection reads call state only.
                    if (!await LauncherService.canDrawOverlays()) {
                      await LauncherService.requestOverlayPermission();
                      if (!await LauncherService.canDrawOverlays()) return;
                    }
                  }
                  await AfterCallService.setEnabled(value);
                  cubit.update(state.copyWith(afterCallEnabled: value));
                },
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'The after-call card needs the "draw over other apps" '
                  'permission to appear on top of the call screen. It does not '
                  'use call-log access and never shows caller names or numbers.',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
