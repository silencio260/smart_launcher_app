import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../state/apps_cubit.dart';
import '../../state/settings_cubit.dart';

class HiddenAppsScreen extends StatelessWidget {
  const HiddenAppsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hidden Apps')),
      body: BlocBuilder<AppsCubit, AppsState>(
        builder: (context, appsState) {
          return BlocBuilder<SettingsCubit, dynamic>(
            builder: (context, settings) {
              final cubit = context.read<SettingsCubit>();
              final settingsCubit = context.read<SettingsCubit>();
              final s = settingsCubit.state;
              final apps = appsState.apps
                ..sort((a, b) => a.name.compareTo(b.name));

              if (apps.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              return ListView.builder(
                itemCount: apps.length,
                itemBuilder: (context, i) {
                  final app = apps[i];
                  final hidden = s.hiddenApps.contains(app.packageName);
                  return CheckboxListTile(
                    title: Text(app.name),
                    subtitle: Text(app.packageName),
                    secondary: app.icon != null
                        ? Image.memory(app.icon!, width: 40, height: 40)
                        : const Icon(Icons.android),
                    value: hidden,
                    onChanged: (v) {
                      if (v == true) {
                        cubit.update(s.copyWith(
                          hiddenApps: [...s.hiddenApps, app.packageName],
                        ));
                      } else {
                        cubit.update(s.copyWith(
                          hiddenApps: s.hiddenApps
                              .where((p) => p != app.packageName)
                              .toList(),
                        ));
                      }
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
