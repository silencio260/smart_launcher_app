import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_info.dart';
import '../models/launcher_feature.dart';
import '../screens/features/alarm_clock_screen.dart';
import '../screens/features/app_locker_screen.dart';
import '../screens/features/file_locker_screen.dart';
import '../screens/settings/hidden_apps_screen.dart';
import '../services/launcher_service.dart';
import '../state/apps_cubit.dart';
import '../state/launcher_feature_cubit.dart';
import '../state/settings_cubit.dart';

class FeatureLaunchDispatcher {
  FeatureLaunchDispatcher._();

  static Future<void> launch(BuildContext context, AppInfo app) async {
    final featureId = app.launcherFeatureId ??
        LauncherFeatureCatalog.idForPackage(app.packageName);
    if (featureId != null) {
      openFeature(context, featureId);
      return;
    }

    final featureSettings = context.read<LauncherFeatureSettingsCubit>().state;
    if (featureSettings.lockedApps.contains(app.packageName)) {
      final unlocked = await LauncherService.authenticateDevice(
        title: 'Unlock ${app.name}',
        description: 'Confirm your device lock to open this app',
      );
      if (!unlocked) return;
    }
    await LauncherService.launchApp(app.packageName);
  }

  static Future<void> launchPackage(
    BuildContext context,
    String packageName,
  ) async {
    final app = context.read<AppsCubit>().state.appsByPackage[packageName] ??
        AppInfo(
          id: packageName.hashCode,
          packageName: packageName,
          appComponentName: packageName,
          title: packageName,
          launcherFeatureId: LauncherFeatureCatalog.idForPackage(packageName),
        );
    await launch(context, app);
  }

  static void openFeature(BuildContext context, String featureId) {
    final screen = switch (featureId) {
      'file_locker' => const FileLockerScreen(),
      'app_hider' => const HiddenAppsScreen(),
      'app_locker' => const AppLockerScreen(),
      'alarm_clock' => const AlarmClockScreen(),
      _ => null,
    };
    if (screen == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<SettingsCubit>()),
            BlocProvider.value(value: context.read<AppsCubit>()),
            BlocProvider.value(
              value: context.read<LauncherFeatureSettingsCubit>(),
            ),
          ],
          child: screen,
        ),
      ),
    );
  }
}
