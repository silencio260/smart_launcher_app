import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smart_launcher_app/core/models/app_info.dart';
import 'package:smart_launcher_app/core/models/launcher_feature.dart';
import 'package:smart_launcher_app/features/clock/presentation/screens/alarm_clock_screen.dart';
import 'package:smart_launcher_app/features/app_hider/presentation/screens/app_hider_screen.dart';
import 'package:smart_launcher_app/features/app_lock/presentation/screens/app_locker_screen.dart';
import 'package:smart_launcher_app/features/file_locker/presentation/screens/file_locker_screen.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/features/apps/presentation/bloc/apps_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/launcher_feature_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';

class FeatureLaunchDispatcher {
  FeatureLaunchDispatcher._();

  static Future<void> launch(BuildContext context, AppInfo app) async {
    final featureId = LauncherFeatureCatalog.idForApp(app);
    if (featureId != null) {
      openFeature(context, featureId);
      return;
    }

    final featureSettings = context.read<LauncherFeatureSettingsCubit>().state;
    if (featureSettings.lockedApps.contains(app.packageName)) {
      // Show the App Lock overlay (PIN/pattern + tap-to-use fingerprint) and let
      // the app launch behind it; the overlay verifies natively and dismisses
      // itself on unlock. No device-credential prompt up front.
      await LauncherService.showAppLockOverlay(app.packageName);
    }
    if (app.appComponentName.contains('/')) {
      await LauncherService.launchComponent(
        packageName: app.packageName,
        componentName: app.appComponentName,
      );
    } else {
      await LauncherService.launchApp(app.packageName);
    }
  }

  static Future<void> launchPackage(
    BuildContext context,
    String packageName,
  ) async {
    final app = context.read<AppsCubit>().state.appsByKey[packageName] ??
        context.read<AppsCubit>().state.appsByPackage[packageName] ??
        AppInfo(
          id: packageName.hashCode,
          packageName: packageName,
          appComponentName: packageName,
          title: packageName,
          launcherFeatureId: LauncherFeatureCatalog.idForPackage(packageName),
        );
    await launch(context, app);
  }

  static Future<void> launchKey(BuildContext context, String key) async {
    final app = context.read<AppsCubit>().state.appsByKey[key] ??
        context.read<AppsCubit>().state.appsByPackage[key];
    if (app != null) await launch(context, app);
  }

  static void openFeature(BuildContext context, String featureId) {
    final screen = switch (featureId) {
      'file_locker' => const FileLockerScreen(),
      'app_hider' => const AppHiderScreen(),
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
