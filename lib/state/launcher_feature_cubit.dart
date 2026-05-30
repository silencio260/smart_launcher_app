import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/launcher_feature_settings.dart';

class LauncherFeatureSettingsCubit extends Cubit<LauncherFeatureSettings> {
  static const _key = 'launcher_feature_settings_v1';

  LauncherFeatureSettingsCubit() : super(const LauncherFeatureSettings());

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      emit(_fromJson(jsonDecode(raw) as Map<String, dynamic>));
    } catch (_) {}
  }

  Future<void> update(LauncherFeatureSettings settings) async {
    emit(settings);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_toJson(settings)));
  }

  Future<void> setAppLocked(String packageName, bool locked) {
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
        'installAssistantEnabled': settings.installAssistantEnabled,
        'promptOnInstall': settings.promptOnInstall,
        'cleanupOnUninstall': settings.cleanupOnUninstall,
        'lockedApps': settings.lockedApps,
      };

  LauncherFeatureSettings _fromJson(Map<String, dynamic> json) {
    return LauncherFeatureSettings(
      overlayMenusEnabled: json['overlayMenusEnabled'] as bool? ?? false,
      afterCallEnabled: json['afterCallEnabled'] as bool? ?? false,
      installAssistantEnabled: json['installAssistantEnabled'] as bool? ?? true,
      promptOnInstall: json['promptOnInstall'] as bool? ?? true,
      cleanupOnUninstall: json['cleanupOnUninstall'] as bool? ?? true,
      lockedApps: (json['lockedApps'] as List?)?.cast<String>() ?? const [],
    );
  }
}
