import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smart_launcher_app/core/analytics/app_events.dart';
import 'package:smart_launcher_app/core/storage/feature_hive_store.dart';
import 'package:smart_launcher_app/core/models/launcher_feature_settings.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';

class LauncherFeatureSettingsCubit extends Cubit<LauncherFeatureSettings> {
  static const _key = 'launcher_feature_settings_v1';
  static const _legacyPrefsKey = 'launcher_feature_settings_v1';

  LauncherFeatureSettingsCubit() : super(const LauncherFeatureSettings());

  Future<void> load() async {
    final dynamic box;
    try {
      box = FeatureHiveStore.box(FeatureHiveBoxes.featureSettings);
    } catch (_) {
      await _syncNativePolicy(state);
      return;
    }
    var raw = box.get(_key);
    raw ??= await _migrateLegacySettings(box);
    if (raw == null) {
      await _syncNativePolicy(state);
      return;
    }
    try {
      final map = raw is String ? jsonDecode(raw) : raw;
      if (map is Map) emit(_fromJson(map.cast<String, dynamic>()));
    } catch (_) {}
    await _syncNativePolicy(state);
  }

  Future<void> update(LauncherFeatureSettings settings) async {
    emit(settings);
    try {
      final box = FeatureHiveStore.box(FeatureHiveBoxes.featureSettings);
      await box.put(_key, _toJson(settings));
    } catch (_) {}
    await _syncNativePolicy(settings);
  }

  Future<void> setAppLocked(String packageName, bool locked) {
    // Count only — never log which package was locked (privacy / Play policy).
    AppAnalytics.appLockToggle(enabled: locked);
    final current = state.lockedApps.toSet();
    if (locked) {
      current.add(packageName);
    } else {
      current.remove(packageName);
    }
    final next = current.toList()..sort();
    return update(state.copyWith(lockedApps: next));
  }

  Map<String, dynamic> _toJson(LauncherFeatureSettings settings) => {
        'overlayMenusEnabled': settings.overlayMenusEnabled,
        'afterCallEnabled': settings.afterCallEnabled,
        'installUninstallAssistantEnabled':
            settings.installUninstallAssistantEnabled,
        'lockedApps': settings.lockedApps,
      };

  LauncherFeatureSettings _fromJson(Map<String, dynamic> json) {
    return LauncherFeatureSettings(
      overlayMenusEnabled: json['overlayMenusEnabled'] as bool? ?? false,
      afterCallEnabled: json['afterCallEnabled'] as bool? ?? false,
      // Fall back to the legacy key for anyone who persisted the old field name.
      installUninstallAssistantEnabled:
          json['installUninstallAssistantEnabled'] as bool? ??
              json['installAssistantEnabled'] as bool? ??
              false,
      lockedApps: (json['lockedApps'] as List?)?.cast<String>() ?? const [],
    );
  }

  Future<Object?> _migrateLegacySettings(dynamic box) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_legacyPrefsKey);
      if (legacy == null) return null;
      final decoded = jsonDecode(legacy) as Map<String, dynamic>;
      await box.put(_key, decoded);
      return decoded;
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncNativePolicy(LauncherFeatureSettings settings) async {
    await LauncherService.setDeviceLockedApps(settings.lockedApps);
  }
}
