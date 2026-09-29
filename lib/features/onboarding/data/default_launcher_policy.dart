import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:genrevibes_developer_access/genrevibes_developer_access.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_launcher_app/bootstrap/app_runtime.dart';
import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/config/app_env.dart';

/// Reads the remote `launcher_force_default` switch (see `LauncherPolicyKeys`).
abstract final class DefaultLauncherPolicy {
  static const _pageZeroKey = 'dev.page_zero_default_prompt';
  static const _appEntryKey = 'dev.app_entry_default_prompt';
  static final appEntryPrompts = ValueNotifier<bool>(true);
  static final pageZeroPrompts = ValueNotifier<bool>(true);
  static final _requests = StreamController<void>.broadcast();
  static Stream<void> get promptRequests => _requests.stream;
  static Future<void>? _loaded;

  static bool get canConfigurePageZero =>
      (kDebugMode || AppEnv.developmentMode) &&
      (_runtime?.developerAccess.allows(DeveloperAction.diagnostics) ?? false);

  static bool get shouldPromptOnAppEntry =>
      !canConfigurePageZero || appEntryPrompts.value;

  static Future<void> loadDeveloperPreference() => _loaded ??= _load();
  static Future<void> _load() async {
    // Read before access initialization if necessary; the getters and setters
    // still require current developer authorization before applying overrides.
    if (!kDebugMode && !AppEnv.developmentMode) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      pageZeroPrompts.value = prefs.getBool(_pageZeroKey) ?? true;
      appEntryPrompts.value = prefs.getBool(_appEntryKey) ?? true;
    } catch (error) {
      debugPrint('Default launcher prompt preference: $error');
    }
  }

  static Future<bool> setPageZeroPrompts(bool enabled) async {
    if (!canConfigurePageZero) return false;
    await loadDeveloperPreference();
    final prefs = await SharedPreferences.getInstance();
    if (!canConfigurePageZero) return false;
    if (!await prefs.setBool(_pageZeroKey, enabled)) return false;
    pageZeroPrompts.value = enabled;
    return true;
  }

  static Future<bool> setAppEntryPrompts(bool enabled) async {
    if (!canConfigurePageZero) return false;
    await loadDeveloperPreference();
    final prefs = await SharedPreferences.getInstance();
    if (!canConfigurePageZero) return false;
    if (!await prefs.setBool(_appEntryKey, enabled)) return false;
    appEntryPrompts.value = enabled;
    return true;
  }

  static Future<void> enteredApp() async {
    await loadDeveloperPreference();
    if (shouldPromptOnAppEntry) requestReturnPrompt();
  }

  /// The gate coalesces events; this never pushes another onboarding route.
  static void requestReturnPrompt() => _requests.add(null);

  static Future<void> returnedFromPageZero() async {
    await loadDeveloperPreference();
    if (canConfigurePageZero && !pageZeroPrompts.value) return;
    requestReturnPrompt();
  }

  static AppRuntime? get _runtime =>
      sl.isRegistered<AppRuntime>() ? sl<AppRuntime>() : null;

  /// True when the launcher may only be used as the default home app.
  static bool get forced => _runtime?.forceDefaultLauncher ?? false;

  /// Fires whenever remote configuration changes, so [forced] can be re-read.
  static Stream<Object?> get changes =>
      _runtime?.remoteConfig.changes ?? const Stream<Object?>.empty();
}
