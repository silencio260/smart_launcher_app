import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/app_info.dart';
import '../../models/launcher_feature.dart';
import '../../models/launcher_feature_settings.dart';
import '../../state/apps_cubit.dart';
import '../../state/launcher_feature_cubit.dart';
import '../../widgets/icons/feature_icon.dart';
import '../../widgets/icons/shaped_icon.dart';

class AppLockerScreen extends StatelessWidget {
  const AppLockerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Locker')),
      body: BlocBuilder<AppsCubit, AppsState>(
        builder: (context, appsState) {
          final apps = appsState.apps
              .where((app) =>
                  !LauncherFeatureCatalog.isFeaturePackage(app.packageName))
              .toList(growable: false);
          if (apps.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          return BlocBuilder<LauncherFeatureSettingsCubit,
              LauncherFeatureSettings>(
            builder: (context, featureSettings) {
              final locked =
                  context.read<LauncherFeatureSettingsCubit>().state.lockedApps;
              final lockedSet = locked.toSet();
              return ListView.builder(
                itemCount: apps.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text(
                        'Safe mode protects apps opened from this launcher.',
                      ),
                    );
                  }
                  final app = apps[index - 1];
                  return SwitchListTile(
                    secondary: _AppIconThumb(app: app),
                    title: Text(app.name),
                    subtitle: Text(app.packageName),
                    value: lockedSet.contains(app.packageName),
                    onChanged: (value) => context
                        .read<LauncherFeatureSettingsCubit>()
                        .setAppLocked(app.packageName, value),
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

class _AppIconThumb extends StatelessWidget {
  final AppInfo app;

  const _AppIconThumb({required this.app});

  @override
  Widget build(BuildContext context) {
    if (app.isInternalFeature) {
      return FeatureIcon(
        featureId: app.launcherFeatureId,
        packageName: app.packageName,
        size: 40,
      );
    }
    return ShapedIcon(
      iconBytes: app.icon,
      iconPath: app.iconPath,
      shape: 'squircle',
      size: 40,
      cacheKey: app.packageName,
    );
  }
}
