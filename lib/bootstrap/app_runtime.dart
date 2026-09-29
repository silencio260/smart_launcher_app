import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:genrevibes_ads/genrevibes_ads.dart';
import 'package:genrevibes_ads_yodo1/genrevibes_ads_yodo1.dart';
import 'package:genrevibes_analytics/genrevibes_analytics.dart';
import 'package:genrevibes_analytics_firebase/genrevibes_analytics_firebase.dart';
import 'package:genrevibes_analytics_mixpanel/genrevibes_analytics_mixpanel.dart';
import 'package:genrevibes_analytics_mixpanel_replay/genrevibes_analytics_mixpanel_replay.dart';
import 'package:genrevibes_app_links/genrevibes_app_links.dart';
import 'package:genrevibes_app_links_launcher/genrevibes_app_links_launcher.dart';
import 'package:genrevibes_app_rating/genrevibes_app_rating.dart';
import 'package:genrevibes_app_rating_in_app_review/genrevibes_app_rating_in_app_review.dart';
import 'package:genrevibes_core/genrevibes_core.dart';
import 'package:genrevibes_crash/genrevibes_crash.dart';
import 'package:genrevibes_crash_crashlytics/genrevibes_crash_crashlytics.dart';
import 'package:genrevibes_developer_access/genrevibes_developer_access.dart';
import 'package:genrevibes_device_identity/genrevibes_device_identity.dart';
import 'package:genrevibes_device_identity_platform/genrevibes_device_identity_platform.dart';
import 'package:genrevibes_devtools/genrevibes_devtools.dart';
import 'package:genrevibes_feedbacknest/genrevibes_feedbacknest.dart';
import 'package:genrevibes_permissions/genrevibes_permissions.dart';
import 'package:genrevibes_permissions_handler/genrevibes_permissions_handler.dart';
import 'package:genrevibes_engagement/genrevibes_engagement.dart';
import 'package:genrevibes_onboarding/genrevibes_onboarding.dart';
import 'package:genrevibes_remote_config/genrevibes_remote_config.dart';
import 'package:genrevibes_remote_config_firebase/genrevibes_remote_config_firebase.dart';
import 'package:genrevibes_remote_config_shared_preferences/genrevibes_remote_config_shared_preferences.dart';
import 'package:genrevibes_remote_policy/genrevibes_remote_policy.dart';
import 'package:genrevibes_starter_kit/genrevibes_starter_kit.dart';
import 'package:genrevibes_storage/genrevibes_storage.dart';
import 'package:genrevibes_storage_shared_preferences/genrevibes_storage_shared_preferences.dart';
import 'package:smart_launcher_app/bootstrap/debug_kit_logger.dart';
import 'package:smart_launcher_app/core/ads/launcher_ads.dart';
import 'package:smart_launcher_app/features/onboarding/data/onboarding_store.dart';
import 'package:smart_launcher_app/core/analytics/analytics_config.dart';
import 'package:smart_launcher_app/core/config/app_env.dart';
import 'package:smart_launcher_app/core/config/launcher_policy_keys.dart';

/// Instances owned by one launcher startup attempt, shared by all consumers.
class AppRuntime extends ChangeNotifier with WidgetsBindingObserver {
  AppRuntime({required this.installId, required this.remoteConfigSchema}) {
    crash = CrashCoordinator(
      reporter: CrashlyticsReporter(logger: logger),
      // Local debug crashes would bury real release regressions.
      config: const CrashReportingConfig(collectionEnabled: !kDebugMode),
      logger: logger,
    );
    remoteConfig = RemoteConfigCoordinator(
      schema: remoteConfigSchema,
      provider: GenRevibesFirebaseRemoteConfigProvider(
        schema: remoteConfigSchema,
        configuration: const GenRevibesFirebaseRemoteConfigConfiguration(
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
      // Analytics collection is a condition of using the launcher and is
      // disclosed in the privacy policy. The only switch is the developer's
      // own remote kill switch on Mixpanel, below.
      sinks: [
        FirebaseAnalyticsSink(logger: logger),
        if (mixpanel case final sink?) sink,
      ],
      observer: eventLog,
      logger: logger,
    );
    store = MigratingKeyValueStore(
      delegate: _preferences,
      legacyKeys: {
        ...EngagementKeys.legacyKeys,
        // The launcher's own completion flag from before the kit controller.
        OnboardingKeys.completed: OnboardingStore.legacyCompletedKey,
      },
    );
    onboarding = OnboardingController(store: store, logger: logger);
    retention = RetentionTracker(
      store: store,
      observer: _LauncherEngagementObserver(this),
    );
    if (AppEnv.yodo1AppKey.trim().isNotEmpty) {
      final provider = Yodo1MasAdProvider(
        configuration: GenRevibesYodo1Configuration(
          appKey: AppEnv.yodo1AppKey,
          // MAS shows its own privacy dialog: the ad network's consent form
          // is the only consent surface in this app.
          useMasPrivacyDialog: true,
        ),
        logger: logger,
        canShowAd: LauncherAds.canShowPlacement,
      );
      adProvider = provider;
      adPolicy = AdPolicyController();
      ads = AdCoordinator(provider: provider, policy: adPolicy!);
      adPolicyBinder = AdsRemotePolicyBinder.forCoordinator(
        remoteConfig,
        policy: adPolicy!,
        placements: LauncherAdPlacements.all,
        logger: logger,
      );
    }
    identity = DeviceIdentityResolver(
      store: store,
      // Vendor id only: the launcher runs no ads, so there is no advertising
      // identifier to resolve and nothing to prompt for.
      vendor: const DeviceInfoVendorIdSource(),
      logger: logger,
    );
    developerAccess = DeveloperAccessController(
      store: store,
      config: DeveloperAccessConfig(
        // `developer_access_store_build` lets a dev build behave like an
        // unlisted store install so the unlock gesture can be exercised.
        isDevelopmentBuild:
            (kDebugMode || AppEnv.developmentMode) &&
            !AppEnv.developerAccessStoreBuild,
        environmentDeviceHashes: AppEnv.developerDeviceHashes,
        passcode: AppEnv.developerPasscode,
      ),
      installMarker: installId,
      logger: logger,
    );
    developerAccessBinder = DeveloperAccessRemotePolicyBinder.forCoordinator(
      remoteConfig,
      controller: developerAccess,
      logger: logger,
    );
    permissionProvider = PermissionHandlerProvider(logger: logger);
    permissions = PermissionCoordinator(
      provider: permissionProvider,
      store: store,
      logger: logger,
    );
    links = AppLinkActions(
      config: AppLinksConfig(
        appName: 'Smart Launcher',
        playStoreUrl: AppEnv.appStoreUrl,
        supportEmail: AppEnv.supportEmail,
        privacyPolicyUrl: AppEnv.privacyPolicyUrl,
        termsUrl: AppEnv.termsUrl.isEmpty ? null : AppEnv.termsUrl,
      ),
      opener: UrlLauncherLinkOpener(),
      isIos: false,
    );
    if (AppEnv.feedBackNestApiKey.isNotEmpty) {
      feedback = FeedbackNestFeedbackProvider(
        configuration: FeedbackNestConfiguration(
          apiKey: AppEnv.feedBackNestApiKey,
          userIdentifier: installId,
        ),
        logger: logger,
      );
    }
    rating = RatingCoordinator(
      store: MigratingKeyValueStore(
        delegate: _preferences,
        legacyKeys: RatingKeys.legacyKeys,
      ),
      logger: logger,
    );
    ratingStore = InAppReviewStoreProvider(
      configuration: InAppReviewConfiguration(
        androidStoreUrl: AppEnv.appStoreUrl,
      ),
      logger: logger,
    );
    replayPolicy = SessionReplayController(
      store: store,
      // Until remote configuration is read this matches the schema default.
      policy: const SessionReplayPolicy(percentOfUsers: 100),
      // A development build seeds "off" so local testing is never recorded;
      // a decision made on the device still wins over this.
      buildOverride: kDebugMode || AppEnv.developmentMode
          ? SessionReplayOverride.forceOff
          : null,
      logger: logger,
    );
    replayPolicyBinder = SessionReplayRemotePolicyBinder.forCoordinator(
      remoteConfig,
      controller: replayPolicy,
      logger: logger,
    );
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
        // Initialized before the first frame: the home gate routes on it.
        StarterModuleRegistration.enabled(
          moduleId: onboarding.moduleId,
          create: () => onboarding,
          isRequired: false,
        ),
        // Ads start after the first frame: the launcher has to be usable
        // before any network SDK gets a turn.
        if (adProvider case final provider?)
          StarterModuleRegistration.deferred(
            moduleId: provider.moduleId,
            create: () => provider,
          ),
        if (adPolicyBinder case final binder?)
          StarterModuleRegistration.deferred(
            moduleId: binder.moduleId,
            create: () => binder,
          ),
        if (feedback case final provider?)
          StarterModuleRegistration.enabled(
            moduleId: provider.moduleId,
            create: () => provider,
            isRequired: false,
          ),
        StarterModuleRegistration.enabled(
          moduleId: permissions.moduleId,
          create: () => permissions,
          isRequired: false,
        ),
        StarterModuleRegistration.enabled(
          moduleId: rating.moduleId,
          create: () => rating,
          isRequired: false,
        ),
        StarterModuleRegistration.enabled(
          moduleId: ratingStore.moduleId,
          create: () => ratingStore,
          isRequired: false,
        ),
        StarterModuleRegistration.enabled(
          moduleId: identity.moduleId,
          create: () => identity,
          isRequired: false,
        ),
        StarterModuleRegistration.enabled(
          moduleId: developerAccess.moduleId,
          create: () => developerAccess,
          isRequired: false,
        ),
        StarterModuleRegistration.enabled(
          moduleId: developerAccessBinder.moduleId,
          create: () => developerAccessBinder,
          isRequired: false,
        ),
        StarterModuleRegistration.enabled(
          moduleId: replayPolicy.moduleId,
          create: () => replayPolicy,
          isRequired: false,
        ),
        StarterModuleRegistration.enabled(
          moduleId: replayPolicyBinder.moduleId,
          create: () => replayPolicyBinder,
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
      onboarding,
      if (feedback != null) feedback!,
      permissions,
      rating,
      ratingStore,
      identity,
      developerAccess,
      developerAccessBinder,
      replayPolicy,
      replayPolicyBinder,
      if (adProvider != null) adProvider!,
      if (adPolicyBinder != null) adPolicyBinder!,
    ]) {
      scope.addModule(module);
    }
    scope.addModule(coordinator);
    // MAS has one interstitial inventory slot. Keep it warm without competing
    // per-screen requests or ever showing from a load/retry callback.
    final adEvents = adProvider?.events.listen((event) {
      if (!scope.isClosed &&
          event.format == AdFormat.interstitial &&
          event.type == AdEventType.dismissed) {
        // The shared policy tracks placement IDs. Apply its configured interval
        // across our interstitial destinations, not just the last-used screen.
        for (final placement in LauncherAdPlacements.all) {
          if (placement.format == AdFormat.interstitial) {
            adPolicy?.recordShown(placement);
          }
        }
      }
    });
    if (adEvents != null) scope.add(adEvents.cancel);
    scope.add(() => _interstitialRetry?.cancel());
    if (ads != null) unawaited(warmInterstitial());
    scope.add(Yodo1InlinePreloads.clear);
    // Continue preparation after the four-second splash. Never auto-show from
    // this worker; only the destination widgets consume its detached cache.
    final inlineWarmup = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!scope.isClosed &&
          (adProvider?.health.isOperational ?? false) &&
          (adPolicyBinder?.health.isOperational ?? false) &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(LauncherAds.prepareInlineAds());
      }
    });
    scope.add(inlineWarmup.cancel);
    final planChanges = replayPolicy.planChanges.listen((_) {
      if (!scope.isClosed) notifyListeners();
    });
    scope.add(planChanges.cancel);
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
  final RemoteConfigSchema remoteConfigSchema;
  late final RemoteConfigCoordinator remoteConfig;

  /// Remote switch: the launcher is unusable until it is the default home app.
  bool get forceDefaultLauncher =>
      remoteConfig.current.read(LauncherPolicyKeys.forceDefaultLauncher);
  late final AnalyticsPipeline analytics;

  /// Mixpanel behind its remote kill switch; null without a token.
  SwitchableAnalyticsSink? mixpanel;
  AnalyticsSinkRemotePolicyBinder? analyticsSwitches;

  /// Runtime permissions the launcher actually asks for.
  ///
  /// Android special access — usage access, notification listener, overlay,
  /// set-as-default — is not a runtime permission and stays app-owned in
  /// [LauncherService] and the mini-app guides.
  late final PermissionCoordinator permissions;

  /// The platform adapter behind [permissions]; Kit Lab reads it directly.
  late final PermissionHandlerProvider permissionProvider;

  /// Store, support and share links for Settings.
  late final AppLinkActions links;

  /// Contact/feedback delivery; null when no FeedbackNest key is configured.
  FeedbackNestFeedbackProvider? feedback;

  /// Decides when the rating prompt may be shown, and remembers the answer.
  late final RatingCoordinator rating;
  late final InAppReviewStoreProvider ratingStore;

  /// Resolves the stable device identity developer recognition uses.
  late final DeviceIdentityResolver identity;

  /// Hidden developer unlock, passcode and recognized-device list.
  late final DeveloperAccessController developerAccess;
  late final DeveloperAccessRemotePolicyBinder developerAccessBinder;

  /// Decides which installs record replay, from the remote rollout.
  late final SessionReplayController replayPolicy;
  late final SessionReplayRemotePolicyBinder replayPolicyBinder;

  late final RetentionTracker retention;

  /// Whether the three onboarding screens were completed. Read by the home
  /// gate, the onboarding flow and Kit Lab.
  late final OnboardingController onboarding;
  late final GenRevibesStarterKit coordinator;

  /// Yodo1 MAS, or null when no app key is configured for this build.
  Yodo1MasAdProvider? adProvider;

  /// Pacing, intervals and the remote master switch.
  AdPolicyController? adPolicy;
  AdsRemotePolicyBinder? adPolicyBinder;

  Timer? _interstitialRetry;
  bool _warmingInterstitial = false;

  /// One runtime-owned load loop. A failed load completes from the SDK callback
  /// (or its bounded deadline); only then does the two-second retry delay begin.
  /// Loaded inventory is retained until an eligible user action consumes it.
  Future<void> warmInterstitial({bool immediate = false}) async {
    if (immediate) _interstitialRetry?.cancel();
    if (scope.isClosed ||
        ads == null ||
        _warmingInterstitial ||
        (_interstitialRetry?.isActive ?? false)) {
      return;
    }
    _warmingInterstitial = true;
    try {
      if (!(adProvider?.health.isOperational ?? false) ||
          !(adPolicyBinder?.health.isOperational ?? false) ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      for (final placement in LauncherAdPlacements.all) {
        final decision = adPolicy?.evaluate(placement);
        // Cooldowns limit display, not preparation of the next creative.
        final mayPreload =
            decision != null &&
            (decision.isAllowed ||
                decision.blockReason == AdPolicyBlockReason.frequencyCap ||
                decision.blockReason == AdPolicyBlockReason.initialDelay);
        if (placement.format != AdFormat.interstitial || !mayPreload) {
          continue;
        }
        if (!adProvider!.isReady(placement)) {
          final result = await ads!.load(placement);
          if (scope.isClosed) return;
          result.fold(
            onSuccess: (_) =>
                debugPrint('LauncherInterstitial: inventory ready'),
            onFailure: (error) => debugPrint(
              'LauncherInterstitial: ${error.message}; retry in 2s when eligible',
            ),
          );
        }
        // All placements share inventory; never issue one request per screen.
        break;
      }
    } catch (error) {
      debugPrint('LauncherInterstitial: load failed: $error; retry in 2s');
    } finally {
      _warmingInterstitial = false;
      if (!scope.isClosed) {
        _interstitialRetry = Timer(const Duration(seconds: 2), () {
          unawaited(warmInterstitial());
        });
      }
    }
  }

  /// Provider plus policy: what app code asks for an ad through.
  AdCoordinator? ads;
  MixpanelReplayController? replay;
  MixpanelSessionReplayRecorder? replayRecorder;
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
    if (identity.health.isOperational) {
      final resolved = await identity.resolve();
      scope.ensureActive();
      resolved.fold(
        // The controller hashes this immediately; the raw value is not kept.
        onSuccess: (value) =>
            developerAccess.setDeviceId(value.vendorId ?? value.installId),
        onFailure: (error) => debugPrint('Device identity: ${error.message}'),
      );
    }
    scope.ensureActive();
    await _startReplay();
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

  /// Brings up the Mixpanel replay SDK for an install the rollout selected.
  ///
  /// Masking and the SDK's own sampling are fixed when it is configured, so
  /// the plan is read once, here, and the recorder is attached with that same
  /// plan. Later rollout changes reach the SDK through the controller.
  Future<void> _startReplay() async {
    if (!AnalyticsConfig.hasMixpanelToken) return;
    final plan = replayPolicy.plan;
    if (!plan.recording) return;
    final controller = MixpanelReplayController(
      configuration: GenRevibesMixpanelReplayConfiguration(
        token: AnalyticsConfig.mixpanelToken,
        distinctId: installId,
      ).withSessionReplay(plan),
      logger: logger,
    );
    replay = controller;
    scope.addModule(controller);
    final started = await controller.initialize();
    check(started);
    if (started.isFailure || scope.isClosed) return;
    final recorder = MixpanelSessionReplayRecorder(
      controller: controller,
      logger: logger,
    );
    replayRecorder = recorder;
    scope.add(recorder.dispose);
    check(await replayPolicy.attach(recorder, configuredPlan: plan));
    notifyListeners();
  }

  /// Work that must wait for the first frame: deferred modules, then a fetch
  /// of fresh remote configuration.
  ///
  /// Initialization only loaded bundled defaults and the last-known-good
  /// cache. This is the call that actually reaches the server, and its result
  /// flows to the policy binders, so nothing here blocks the first screen.
  Future<void>? _deferredWork;
  Future<void> startDeferredWork() => _deferredWork ??= _startDeferredWork();

  Future<void> _startDeferredWork() async {
    if (scope.isClosed) return;
    await coordinator.startDeferred();
    if (scope.isClosed) return;
    if (remoteConfig.health.isOperational) {
      check(await remoteConfig.refresh());
    }
    if (scope.isClosed) return;
    // Also covers SDK startup finishing after the splash's short deadline.
    unawaited(LauncherAds.prepareInlineAds());
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
      unawaited(LauncherAds.onResumed());
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

  /// Pauses recording inside Vault, App Lock, App Hider and File Locker.
  ///
  /// Leaving re-applies the rollout rather than starting recording outright,
  /// so a device that should not record does not begin doing so on the way
  /// out of a secure screen.
  void _syncReplay() {
    _replayWork = _replayWork
        .then<void>((_) async {
          final recorder = replayRecorder;
          if (recorder == null || scope.isClosed) return;
          check(
            await (_privateScreens > 0
                ? recorder.stopRecording()
                : replayPolicy.applyPolicy(replayPolicy.policy)),
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
