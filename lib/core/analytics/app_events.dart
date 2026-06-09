import 'package:genrevibes_starter_kit/starter_kit.dart';

import 'crash_context.dart';

/// App-side analytics facade.
///
/// Centralizes event names + typed helpers so feature code never hand-types
/// event strings. Every call delegates to [StarterKit.analytics], which fans out
/// to BOTH Firebase and Mixpanel (see the metric catalog / plan Parts C0–C7).
///
/// Privacy rules baked in here (plan Part D):
///   * NO third-party package/app names — external launches log source + counts.
///   * NO raw search text / PINs / patterns / file names — only lengths & flags.
///   * Secure mini-apps hard-stop Mixpanel session replay on entry.
class AppAnalytics {
  AppAnalytics._();

  static AnalyticsService get _a => StarterKit.analytics;
  static bool get _analyticsReady =>
      StarterKit.sl.isRegistered<AnalyticsBloc>();

  /// Identifiers for our own mini-apps.
  static const miniAppClock = 'clock';
  static const miniAppVault = 'vault';
  static const miniAppAppLock = 'app_lock';
  static const miniAppAppHider = 'app_hider';
  static const miniAppFileLocker = 'file_locker';
  static const miniAppSearch = 'search';
  static const miniAppDiscover = 'discover';
  static const miniAppLibrary = 'app_library';

  /// Mini-apps that show private content/credentials — replay is stopped inside.
  static const _secureMiniApps = {
    miniAppVault,
    miniAppAppLock,
    miniAppAppHider,
    miniAppFileLocker,
  };

  // --- Generic passthroughs ---

  static void event(String name, {Map<String, dynamic>? params}) {
    if (_analyticsReady) {
      _a.logEvent(name, parameters: params);
    }
    CrashContext.log(name);
  }

  static void screenView(String screen) {
    if (_analyticsReady) {
      _a.logScreenView(screen);
    }
    CrashContext.setActiveScreen(screen);
  }

  static void setUserProperty(String name, String value) {
    if (_analyticsReady) {
      _a.setUserProperty(name, value);
    }
  }

  // --- C0: lifecycle & user model ---

  static void appOpen() {
    if (_analyticsReady) {
      _a.logAppOpen();
    }
  }

  static void launcherSetDefault(bool isDefault) {
    event('launcher_set_default', params: {'is_default': isDefault});
    setUserProperty('default_launcher', '$isDefault');
    CrashContext.setBool('default_launcher', isDefault);
  }

  // --- C1: home / workspace (aggregate only — NO package names) ---

  /// External (third-party) app launched. Logs source + position only.
  static void appLaunched({required String source, int? position}) => event(
        'app_launched',
        params: {'source': source, if (position != null) 'position': position},
      );

  static void workspacePageChanged({
    required int fromIndex,
    required int toIndex,
    required String type,
  }) =>
      event('workspace_page_changed', params: {
        'from_index': fromIndex,
        'to_index': toIndex,
        'type': type,
      });

  static void folderOpened({int? itemCount}) => event('folder_opened',
      params: {if (itemCount != null) 'item_count': itemCount});

  static void homeEditMode() => event('home_edit_mode');

  static void drawerOpened({required String openMethod}) =>
      event('drawer_opened', params: {'open_method': openMethod});

  static void appContextMenuOpened({required int actionsAvailable}) =>
      event('app_context_menu_opened',
          params: {'actions_available': actionsAvailable});

  // --- Ads test instrumentation ---

  static void adLifecycle({
    required String adType,
    required String action,
    required String result,
    String source = 'dev_panel',
    bool testAds = true,
    String? error,
  }) =>
      event('ad_lifecycle', params: {
        'ad_type': adType,
        'action': action,
        'result': result,
        'source': source,
        'test_ads': testAds,
        if (error != null) 'error': error,
      });

  // --- C2: smart search (NO raw query text) ---

  static void searchOpened({required String source}) =>
      event('search_opened', params: {'source': source});

  static void searchPerformed({
    required int queryLength,
    required int resultCount,
  }) =>
      event('search_performed', params: {
        'query_length': queryLength,
        'result_count': resultCount,
        'has_results': resultCount > 0,
      });

  static void searchResultTapped({
    required String resultType,
    required int resultIndex,
  }) =>
      event('search_result_tapped',
          params: {'result_type': resultType, 'result_index': resultIndex});

  static void searchRecentRerun() => event('search_recent_rerun');

  // --- C3: secure mini-apps (replay OFF inside) ---

  /// Call on entering ANY mini-app. For secure mini-apps this also hard-stops
  /// Mixpanel session replay. Pair with [miniAppClosed].
  static void miniAppOpened(String miniApp) {
    event('mini_app_open', params: {'mini_app': miniApp});
    CrashContext.setActiveMiniApp(miniApp);
    if (_secureMiniApps.contains(miniApp)) {
      StarterKit.mixpanel?.stopReplay();
    }
  }

  /// Call on leaving a mini-app. Resumes replay if it was a secure one.
  static void miniAppClosed(String miniApp) {
    CrashContext.setActiveMiniApp(null);
    if (_secureMiniApps.contains(miniApp)) {
      StarterKit.mixpanel?.startReplay();
    }
  }

  static void secureAuthAttempt({
    required String miniApp,
    required String method,
  }) =>
      event('secure_auth_attempt',
          params: {'mini_app': miniApp, 'method': method});

  static void secureAuthResult({
    required String miniApp,
    required String method,
    required bool success,
  }) =>
      event('secure_auth_result', params: {
        'mini_app': miniApp,
        'method': method,
        'success': success,
      });

  static void vaultItemImported(
          {required String mediaType, required int count}) =>
      event('vault_item_imported',
          params: {'media_type': mediaType, 'count': count});

  static void vaultItemExported({required int count}) =>
      event('vault_item_exported', params: {'count': count});

  static void appLockToggle({required bool enabled}) =>
      event('app_lock_toggle', params: {'enabled': enabled});

  static void appLockChallengeShown({required String strategy}) =>
      event('app_lock_challenge_shown', params: {'strategy': strategy});

  static void appHiderToggle({required bool hidden}) =>
      event('app_hider_toggle', params: {'hidden': hidden});

  static void appHiderDisguiseSet({required String disguiseId}) =>
      event('app_hider_disguise_set', params: {'disguise_id': disguiseId});

  static void fileLockerAction({required String action, String? fileType}) =>
      event('file_locker_action', params: {
        'action': action,
        if (fileType != null) 'file_type': fileType,
      });

  // --- C4: clock / alarm ---

  static void alarmCreated({required bool repeat, required bool hasSound}) =>
      event('alarm_created', params: {'repeat': repeat, 'has_sound': hasSound});

  static void alarmEdited({String? fieldChanged}) => event('alarm_edited',
      params: {if (fieldChanged != null) 'field_changed': fieldChanged});

  static void alarmDeleted() => event('alarm_deleted');

  static void alarmToggled({required bool enabled}) =>
      event('alarm_toggled', params: {'enabled': enabled});

  static void alarmFired({required bool snoozed}) =>
      event('alarm_fired', params: {'snoozed': snoozed});

  static void worldClockAdded() => event('world_clock_added');

  // --- C5: discover & app library ---

  static void discoverOpened() => event('discover_opened');

  static void discoverArticleOpened({String? sourceName, int? position}) =>
      event('discover_article_opened', params: {
        if (sourceName != null) 'source_name': sourceName,
        if (position != null) 'position': position,
      });

  static void discoverSourcesOpened() => event('discover_sources_opened');

  static void discoverSuggestionLaunched({int? position}) =>
      event('discover_suggestion_launched',
          params: {if (position != null) 'position': position});

  static void appLibraryOpened() => event('app_library_opened');

  static void appLibraryCategoryOpened({required String category}) =>
      event('app_library_category_opened', params: {'category': category});

  // --- C6: settings & feature flags ---

  static void settingsOpened() => event('settings_opened');

  static void settingsSubpageOpened({required String page}) =>
      event('settings_subpage_opened', params: {'page': page});

  static void featureToggled(
          {required String featureId, required bool enabled}) =>
      event('feature_toggled',
          params: {'feature_id': featureId, 'enabled': enabled});

  static void appearanceChanged(
          {required String setting, required String value}) =>
      event('appearance_changed', params: {'setting': setting, 'value': value});

  static void gestureSet({required String gesture, required String action}) =>
      event('gesture_set', params: {'gesture': gesture, 'action': action});

  static void settingsExport({required bool success}) =>
      event('settings_export', params: {'success': success});
}
