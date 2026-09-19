import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:genrevibes_ads/genrevibes_ads.dart';
import 'package:genrevibes_ads_admob/genrevibes_ads_admob.dart';
import 'package:genrevibes_analytics/genrevibes_analytics.dart';
import 'package:genrevibes_analytics_firebase/genrevibes_analytics_firebase.dart';
import 'package:genrevibes_analytics_mixpanel/genrevibes_analytics_mixpanel.dart';
import 'package:genrevibes_analytics_mixpanel_replay/genrevibes_analytics_mixpanel_replay.dart';
import 'package:genrevibes_core/genrevibes_core.dart';
import 'package:genrevibes_crash/genrevibes_crash.dart';
import 'package:genrevibes_crash_crashlytics/genrevibes_crash_crashlytics.dart';
import 'package:genrevibes_devtools/genrevibes_devtools.dart';
import 'package:genrevibes_engagement/genrevibes_engagement.dart';
import 'package:genrevibes_remote_config/genrevibes_remote_config.dart';
import 'package:genrevibes_remote_config_firebase/genrevibes_remote_config_firebase.dart';
import 'package:genrevibes_remote_config_shared_preferences/genrevibes_remote_config_shared_preferences.dart';
import 'package:genrevibes_remote_policy/genrevibes_remote_policy.dart';
import 'package:genrevibes_starter_kit/genrevibes_starter_kit.dart';
import 'package:genrevibes_storage/genrevibes_storage.dart';
import 'package:genrevibes_storage_shared_preferences/genrevibes_storage_shared_preferences.dart';
import 'package:smart_launcher_app/bootstrap/debug_kit_logger.dart';
import 'package:smart_launcher_app/core/ads/test_ads_config.dart';
import 'package:smart_launcher_app/core/analytics/analytics_config.dart';
import 'package:smart_launcher_app/core/config/app_env.dart';

/// Instances owned by one launcher startup attempt, shared by all consumers.
class AppRuntime extends ChangeNotifier with WidgetsBindingObserver {
  AppRuntime({required this.installId}) {
    crash = CrashCoordinator(
      reporter: CrashlyticsReporter(logger: logger),
      // Local debug crashes would bury real release regressions.
      config: const CrashReportingConfig(collectionEnabled: !kDebugMode),
      logger: logger,
    );
    remoteConfigSchema = PortfolioRemoteConfigSchema.build(
      // The launcher already records every release session; remote config
      // lowers this, it does not have to raise it first.
      replayDefaults: const SessionReplayPolicy(percentOfUsers: 100),
    );
    remoteConfig = RemoteConfigCoordinator(
      schema: remoteConfigSchema,
      provider: GenRevibesFirebaseRemoteConfigProvider(
        schema: remoteConfigSchema,
        configuration:
            const GenRevibesFirebaseRemoteConfigConfiguration(
              fetchTimeout: PortfolioRemoteConfigSettings.fetchTimeout,
              minimumFetchInterval:
                  PortfolioRemoteConfigSettings.minimumFetchInterval,
            ),
        logger: logger,
      ),
      // Last-known-good values, so a launch with no network still applies the
      // policy this device saw last time instead of the bundled defaults.
      cache: SharedPreferencesRemoteConfigCache(),
      logger: logger,
    );
    mixpanel = AnalyticsConfig.hasMixpanelToken
        ? SwitchableAnalyticsSink(
            MixpanelAnalyticsSink(
              configuration: GenRevibesMixpanelConfiguration(
                token: AnalyticsConfig.mixpanelToken,
              ),
              logger: logger,
            ),
            // Real value applied by the binder once remote config is loaded.
            enabled: true,
            logger: logger,
          )
        : null;
    analytics = AnalyticsPipeline(
      sinks: [
        FirebaseAnalyticsSink(logger: logger),
        if (mixpanel case final sink?) sink,
      ],
      observer: eventLog,
      logger: logger,
    );
    store = MigratingKeyValueStore(
      delegate: _preferences,
      legacyKeys: EngagementKeys.legacyKeys,
    );
    retention = RetentionTracker(
      store: store,
      observer: _LauncherEngagementObserver(this),
    );
    final config = TestAdsConfig.fromAppEnv();
    if (config != null) {
      ads = AdMobAdProvider(configuration: config, testMode: true);
    }
    if (AnalyticsConfig.hasMixpanelToken &&
        !kDebugMode &&
        !AppEnv.developmentMode) {
      replay = MixpanelReplayController(
        configuration: GenRevibesMixpanelReplayConfiguration(
          token: AnalyticsConfig.mixpanelToken,
          distinctId: installId,
          // Preserve the existing release rollout and masking policy.
          sessionsPercent: 100,
        ),
      );
    }
    if (mixpanel case final sink?) {
      analyticsSwitches = AnalyticsSinkRemotePolicyBinder.forCoordinator(
        remoteConfig,
        sinks: [sink],
        logger: logger,
      );
    }
    coordinator = GenRevibesStarterKit(
      autoStartDeferred: false,
      modules: [
        StarterModuleRegistration.enabled(
          moduleId: crash.moduleId,
          create: () => crash,
          isRequired: false,
        ),
        StarterModuleRegistration.enabled(
          moduleId: remoteConfig.moduleId,
          create: () => remoteConfig,
          isRequired: false,
        ),
        StarterModuleRegistration.enabled(
          moduleId: analytics.moduleId,
          create: () => analytics,
          isRequired: false,
        ),
        if (analyticsSwitches case final binder?)
          StarterModuleRegistration.enabled(
            moduleId: binder.moduleId,
            create: () => binder,
            isRequired: false,
          ),
        StarterModuleRegistration.enabled(
          moduleId: retention.moduleId,
          create: () => retention,
          isRequired: false,
        ),
        if (ads case final provider?)
          StarterModuleRegistration.deferred(
            moduleId: provider.moduleId,
            create: () => provider,
          ),
        if (replay case final recorder?)
          StarterModuleRegistration.enabled(
            moduleId: recorder.moduleId,
            create: () => recorder,
            isRequired: false,
          ),
      ],
    );
    // Own even the deferred instances if the app closes before their startup.
    for (final module in <StarterModule>[
      crash,
      remoteConfig,
      analytics,
      if (analyticsSwitches case final binder?) binder,
      retention,
      if (ads != null) ads!,
      if (replay != null) replay!,
    ]) {
      scope.addModule(module);
    }
    scope.addModule(coordinator);
    final recorder = replay;
    if (recorder != null) {
      final subscription = recorder.healthChanges.listen((health) {
        if (scope.isClosed) return;
        if (health.isOperational && _privateScreens > 0) _syncReplay();
        notifyListeners();
      });
      scope.add(subscription.cancel);
    }
  }

  final String installId;
  final scope = KitResourceScope();

  /// Kit log history for Kit Lab, mirrored to the console.
  final logger = RecordingKitLogger(forwardTo: const DebugKitLogger());

  /// Delivered-event history for Kit Lab.
  final eventLog = RecordingDeliveryObserver();
  final _preferences = SharedPreferencesKeyValueStore();
  late final KeyValueStore store;
  late final CrashCoordinator crash;
  late final RemoteConfigSchema remoteConfigSchema;
  late final RemoteConfigCoordinator remoteConfig;
  late final AnalyticsPipeline analytics;

  /// Mixpanel behind its remote kill switch; null without a token.
  SwitchableAnalyticsSink? mixpanel;
  AnalyticsSinkRemotePolicyBinder? analyticsSwitches;
  late final RetentionTracker retention;
  late final GenRevibesStarterKit coordinator;
  AdProvider? ads;
  MixpanelReplayController? replay;
  int totalSessions = 0;
  int _privateScreens = 0;
  bool _backgrounded = false;
  bool _retentionReady = false;
  Future<void> _sessionWork = Future<void>.value();
  Future<void> _replayWork = Future<void>.value();

  Future<void> initialize() async {
    await _prepareHistory().timeout(const Duration(seconds: 10));
    scope.ensureActive();
    check(await coordinator.initialize());
    scope.ensureActive();
    for (final id in coordinator.registeredModuleIds) {
      final error = coordinator.moduleHealth(id)?.error;
      if (error != null) debugPrint('Starter kit $id: ${error.message}');
    }
    // Framework, platform and zone errors reach Crashlytics through the
    // coordinator from here on. Restoring is registered first so a later
    // failure in this attempt cannot leave the hooks pointing at a dead
    // runtime.
    final hooks = CrashHooks.install(crash);
    scope.add(hooks.restore);
    if (crash.health.isOperational) {
      check(await crash.identify(installId));
    }
    if (analytics.health.isOperational) {
      try {
        check(
          await analytics
              .identify(AnalyticsUser(id: installId))
              .timeout(const Duration(seconds: 10)),
        );
      } catch (error) {
        debugPrint('Analytics identity: $error');
      }
    }
    scope.ensureActive();
    if (retention.health.isOperational && retention.health.error == null) {
      _retentionReady = true;
      _sessionWork = _recordSession(open: true);
      // Local persistence must not keep the launcher behind startup forever.
      try {
        await _sessionWork.timeout(const Duration(seconds: 10));
      } catch (error) {
        debugPrint('Retention startup: $error');
      }
    }
    scope.ensureActive();
    WidgetsBinding.instance.addObserver(this);
    scope.add(() => WidgetsBinding.instance.removeObserver(this));
  }

  /// Work that must wait for the first frame: deferred modules, then a fetch
  /// of fresh remote configuration.
  ///
  /// Initialization only loaded bundled defaults and the last-known-good
  /// cache. This is the call that actually reaches the server, and its result
  /// flows to the policy binders, so nothing here blocks the first screen.
  Future<void> startDeferredWork() async {
    if (scope.isClosed) return;
    await coordinator.startDeferred();
    if (scope.isClosed) return;
    if (remoteConfig.health.isOperational) {
      check(await remoteConfig.refresh());
    }
  }

  /// Preflight migration so the kit cannot replace unreadable saved history.
  Future<void> _prepareHistory() async {
    Future<void> migrate<T extends Object>(
      String key,
      Future<KitResult<T?>> Function(String) read,
      Future<KitResult<void>> Function(String, T) write,
    ) async {
      final current = require(await read(key));
      scope.ensureActive();
      if (current != null) return;
      final legacy = require(await read(EngagementKeys.legacyKeys[key]!));
      scope.ensureActive();
      if (legacy != null) require(await write(key, legacy));
    }

    for (final key in [
      EngagementKeys.installedAt,
      EngagementKeys.lastOpenedAt,
    ]) {
      await migrate(key, _preferences.getString, _preferences.setString);
    }
    await migrate(
      EngagementKeys.totalOpens,
      _preferences.getInt,
      _preferences.setInt,
    );
    for (final key in [
      EngagementKeys.sessionTimestamps,
      EngagementKeys.dailyOpenDates,
    ]) {
      await migrate(
        key,
        _preferences.getStringList,
        _preferences.setStringList,
      );
    }
    totalSessions =
        require(await _preferences.getInt('total_sessions')) ??
        (require(
              await store.getStringList(EngagementKeys.sessionTimestamps),
            )?.length ??
            0);
  }

  Future<void> _recordSession({bool open = false}) async {
    if (scope.isClosed || !_retentionReady) return;
    final nextTotal = totalSessions + 1;
    final saved = await _preferences.setInt('total_sessions', nextTotal);
    check(saved);
    if (saved.isFailure) return;
    totalSessions = nextTotal;
    if (scope.isClosed) return;
    check(await (open ? retention.recordAppOpen() : retention.recordSession()));
    if (!scope.isClosed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _backgrounded = true;
    if (state == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      _sessionWork = _sessionWork
          .then((_) => _recordSession())
          .catchError((Object error) => debugPrint('Retention: $error'));
    }
  }

  void enterPrivateScreen() {
    _privateScreens++;
    _syncReplay();
  }

  void leavePrivateScreen() {
    if (_privateScreens > 0) _privateScreens--;
    _syncReplay();
  }

  void _syncReplay() {
    _replayWork = _replayWork
        .then<void>((_) async {
          final recorder = replay;
          if (recorder == null || scope.isClosed) return;
          check(
            await (_privateScreens > 0 ? recorder.stop() : recorder.start()),
          );
        })
        .catchError((Object error) => debugPrint('Replay: $error'));
  }

  static T require<T>(KitResult<T> result) => result.fold(
    onSuccess: (value) => value,
    onFailure: (error) => throw StateError(error.message),
  );

  static void check<T>(KitResult<T> result) => result.fold(
    onSuccess: (_) {},
    onFailure: (error) => debugPrint('Starter kit: ${error.message}'),
  );

  @override
  void dispose() {
    unawaited(scope.dispose().then(check));
    super.dispose();
  }
}

/// Adds the launcher's lifetime counter to shared retention events.
class _LauncherEngagementObserver implements EngagementObserver {
  _LauncherEngagementObserver(this.runtime);
  final AppRuntime runtime;

  void track(String name, Map<String, Object?> properties) {
    unawaited(
      runtime.analytics
          .track(
            AnalyticsEvent(
              name: name,
              properties: {
                ...properties,
                'total_sessions': runtime.totalSessions,
              },
            ),
          )
          .then(AppRuntime.check),
    );
  }

  @override
  void onAppOpened(EngagementSnapshot snapshot) {
    track(EngagementEvents.appOpened, snapshot.toProperties());
    _ordinal('open', snapshot.totalOpens, snapshot);
    _ordinal('session', runtime.totalSessions, snapshot);
    // Preserve the launcher's additional day milestones.
    if ([0, 10, 15, 20, 25].contains(snapshot.daysSinceInstall)) {
      track(
        'retention_day_${snapshot.daysSinceInstall}_returned',
        snapshot.toProperties(),
      );
    }
  }

  @override
  void onSessionStarted(EngagementSnapshot snapshot) {
    track(EngagementEvents.sessionStarted, snapshot.toProperties());
    _ordinal('session', runtime.totalSessions, snapshot);
  }

  void _ordinal(String kind, int count, EngagementSnapshot snapshot) {
    const ordinals = ['first', 'second', 'third', 'fourth', 'fifth'];
    if (count > 0 && count <= ordinals.length) {
      track('retention_${ordinals[count - 1]}_$kind', snapshot.toProperties());
    }
  }

  @override
  void onMilestone(RetentionMilestone milestone, EngagementSnapshot snapshot) =>
      track('retention_day_${milestone.day}_returned', snapshot.toProperties());

  @override
  void onProfileEvaluated(UserProfile profile) {
    track(EngagementEvents.segmentUpdate, profile.toProperties());
    if (profile.isLoyal) {
      track(EngagementEvents.userIsLoyal, profile.toProperties());
    }
    if (profile.isPowerUser) {
      track(EngagementEvents.userIsPowerUser, profile.toProperties());
    }
  }
}
