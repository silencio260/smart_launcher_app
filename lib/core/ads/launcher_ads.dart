import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:genrevibes_ads/genrevibes_ads.dart';
import 'package:genrevibes_ads_yodo1/genrevibes_ads_yodo1.dart';
import 'package:genrevibes_remote_policy/genrevibes_remote_policy.dart';
import 'package:smart_launcher_app/bootstrap/app_runtime.dart';
import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/analytics/app_events.dart';
import 'package:smart_launcher_app/features/onboarding/data/onboarding_store.dart';

/// Where the launcher is allowed to show an ad.
///
/// Fullscreen formats share MAS inventory; embedded views are cached separately
/// by placement so that one screen never consumes another screen's native ad.
abstract final class LauncherAdPlacements {
  /// Interstitial shown when the user opens a mini-app.
  static const miniAppOpen = AdPlacement(
    id: 'mini_app_open',
    format: AdFormat.interstitial,
  );

  /// App-open ad, only ever while a mini-app is in front.
  static const appOpen = AdPlacement(
    id: 'mini_app_resume',
    format: AdFormat.appOpen,
  );

  /// Banner at the bottom of a mini-app screen.
  static const miniAppBanner = AdPlacement(
    id: 'mini_app_banner',
    format: AdFormat.banner,
  );

  static const discoverNative = AdPlacement(
    id: 'discover_feed',
    format: AdFormat.native,
  );
  static const drawerNative = AdPlacement(
    id: 'app_drawer',
    format: AdFormat.native,
  );
  static const discoverSlots = <AdPlacement>[
    discoverNative,
    AdPlacement(id: 'discover_feed_2', format: AdFormat.native),
    AdPlacement(id: 'discover_feed_3', format: AdFormat.native),
    AdPlacement(id: 'discover_feed_4', format: AdFormat.native),
    AdPlacement(id: 'discover_feed_5', format: AdFormat.native),
  ];
  static const drawerSlots = <AdPlacement>[
    drawerNative,
    AdPlacement(id: 'app_drawer_2', format: AdFormat.native),
  ];
  static const wallpaperBanner = AdPlacement(
    id: 'wallpaper_banner',
    format: AdFormat.banner,
  );
  static const themesBanner = AdPlacement(
    id: 'themes_banner',
    format: AdFormat.banner,
  );
  static const settingsBanner = AdPlacement(
    id: 'settings_banner',
    format: AdFormat.banner,
  );
  static const wallpaperApplied = AdPlacement(
    id: 'wallpaper_applied',
    format: AdFormat.interstitial,
  );
  static const themeApplied = AdPlacement(
    id: 'theme_applied',
    format: AdFormat.interstitial,
  );
  static const settingsChanged = AdPlacement(
    id: 'settings_changed',
    format: AdFormat.interstitial,
  );
  static const actionInterstitials = [
    wallpaperApplied,
    themeApplied,
    settingsChanged,
  ];
  static const libraryNative = AdPlacement(
    id: 'app_library',
    format: AdFormat.native,
  );
  static const searchNative = AdPlacement(
    id: 'idle_search',
    format: AdFormat.native,
  );

  /// Native ad on the onboarding screen(s) that have an ad slot.
  static const onboardingNative = AdPlacement(
    id: 'onboarding',
    format: AdFormat.native,
  );

  /// Every placement the app declares, for remote policy and Kit Lab.
  static const all = <AdPlacement>[
    miniAppOpen,
    appOpen,
    miniAppBanner,
    ...discoverSlots,
    ...drawerSlots,
    wallpaperBanner,
    themesBanner,
    settingsBanner,
    ...actionInterstitials,
    libraryNative,
    searchNative,
    onboardingNative,
  ];
}

/// The launcher's ad rules.
///
/// Full-screen ads are confined to mini-apps and completed customization actions.
/// Inline native ads have their own
/// explicitly selected slots on Discover, the drawer, App Library and idle
/// search. Regular workspace pages and folder views remain ad-free.
///
/// Pacing, intervals and the master switch come from remote config through
/// `AdPolicyController`; this class only decides *where* a request is even
/// considered.
abstract final class LauncherAds {
  static const nativeWidth = 300.0;
  static const nativeHeight = 100.0;
  static bool _insideMiniApp = false;
  static bool Function()? _actionGuard;
  static AdPlacement? _actionPlacement;
  static int _settingsCompletions = 0;

  /// Checked by the provider again after its asynchronous readiness check.
  static bool canShowPlacement(AdPlacement placement) {
    if (LauncherAdPlacements.actionInterstitials.contains(placement)) {
      return placement == _actionPlacement && (_actionGuard?.call() ?? false);
    }
    return canShowMiniAppAd;
  }

  static Future<void> preloadAction(AdPlacement placement) async {
    if (!LauncherAdPlacements.actionInterstitials.contains(placement)) {
      return;
    }
    await _runtime?.warmInterstitial();
  }

  /// A completed action may consume ready inventory, never wait for a load.
  /// Route, foreground and a short presentation window prevent late ads on Home.
  static Future<void> onActionCompleted(
    BuildContext context,
    AdPlacement placement,
  ) async {
    if (!context.mounted ||
        !LauncherAdPlacements.actionInterstitials.contains(placement)) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route?.isCurrent != true) return;
    if (placement == LauncherAdPlacements.settingsChanged &&
        ++_settingsCompletions % 3 != 0) {
      unawaited(preloadAction(placement));
      return;
    }
    final now = DateTime.now();
    if (_actionGuard != null) return;
    final ads = _ads;
    if (ads == null || !ads.provider.isReady(placement)) {
      unawaited(preloadAction(placement));
      return;
    }
    bool policyStillAllows() {
      final policy = _runtime?.adPolicy;
      if (policy == null) return false;
      final decision = policy.evaluate(placement);
      return decision.isAllowed ||
          (decision.blockReason == AdPolicyBlockReason.anotherAdShowing &&
              policy.showingPlacement == placement);
    }

    bool allowed() =>
        context.mounted &&
        route!.isCurrent &&
        policyStillAllows() &&
        !launchPreparing &&
        !defaultPromptVisible &&
        DateTime.now().difference(now) < const Duration(milliseconds: 800) &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (!allowed()) return;
    _actionPlacement = placement;
    _actionGuard = allowed;
    try {
      final result = await ads.show(placement);
      result.fold(
        onSuccess: (outcome) {
          AppAnalytics.adLifecycle(
            adType: 'interstitial',
            action: 'show',
            result: outcome.status.name,
            source: placement.id,
            testAds: false,
          );
        },
        onFailure: (error) {
          AppAnalytics.adLifecycle(
            adType: 'interstitial',
            action: 'show',
            result: 'failure',
            source: placement.id,
            testAds: false,
            error: error.message,
          );
        },
      );
    } catch (error) {
      // An optional ad failure must not turn a successful saved action into an
      // error or prevent the wallpaper preview from closing normally.
      debugPrint('LauncherActionAd [${placement.id}] show failed: $error');
    } finally {
      _actionGuard = null;
      _actionPlacement = null;
      unawaited(preloadAction(placement));
    }
  }

  /// Prevent existing mini-app resume logic from opening an ad over preparation.
  static bool launchPreparing = false;
  static bool defaultPromptVisible = false;

  static bool get canShowMiniAppAd {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return _insideMiniApp &&
        !launchPreparing &&
        !defaultPromptVisible &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
  }

  static final _preloading = <String, Future<bool>>{};
  static final _lastPreloadAttempt = <String, DateTime>{};
  static final _mountedInline = <String, int>{};

  static void inlineMounted(AdPlacement placement) => _mountedInline.update(
    placement.id,
    (count) => count + 1,
    ifAbsent: () => 1,
  );

  static void inlineUnmounted(AdPlacement placement) {
    final count = _mountedInline[placement.id] ?? 0;
    if (count <= 1) {
      _mountedInline.remove(placement.id);
    } else {
      _mountedInline[placement.id] = count - 1;
    }
  }

  /// The splash may wait for this, but regular launcher launches never have to.
  /// Existing deferred startup owns SDK/consent; no second initializer is used.
  static Future<void> prepareInlineAds() async {
    final runtime = _runtime;
    if (runtime?.adProvider == null ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final deadline = DateTime.now().add(const Duration(seconds: 7));
    while (!runtime!.scope.isClosed &&
        (!(runtime.adProvider?.health.isOperational ?? false) ||
            !(runtime.adPolicyBinder?.health.isOperational ?? false))) {
      if (DateTime.now().isAfter(deadline)) {
        debugPrint(
          'LauncherInlinePreload: startup not ready within 7s; '
          'provider=${runtime.adProvider?.health.state.name}, '
          'policy=${runtime.adPolicyBinder?.health.state.name}',
        );
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (runtime.scope.isClosed) return;
    final placements = !OnboardingStore.isCompletedSync
        ? [LauncherAdPlacements.onboardingNative]
        : [
            LauncherAdPlacements.discoverNative,
            LauncherAdPlacements.drawerNative,
            LauncherAdPlacements.libraryNative,
            LauncherAdPlacements.searchNative,
            LauncherAdPlacements.miniAppBanner,
          ];
    await Future.wait(placements.map(preloadInline));
  }

  /// Rechecks policy at request time; destinations separately recheck at mount.
  static Future<bool> preloadInline(AdPlacement placement) async {
    final runtime = _runtime;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (runtime == null ||
        runtime.scope.isClosed ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
        !(runtime.adProvider?.health.isOperational ?? false) ||
        !(runtime.adPolicyBinder?.health.isOperational ?? false) ||
        !(runtime.adPolicy?.evaluate(placement).isAllowed ?? false) ||
        _mountedInline.containsKey(placement.id) ||
        (placement == LauncherAdPlacements.onboardingNative &&
            !onboardingAdAllowed)) {
      return false;
    }
    final existing = _preloading[placement.id];
    if (existing != null) return existing;
    final lastAttempt = _lastPreloadAttempt[placement.id];
    if (lastAttempt != null &&
        DateTime.now().difference(lastAttempt) < const Duration(seconds: 2)) {
      return false;
    }
    _lastPreloadAttempt[placement.id] = DateTime.now();
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return false;
    // Match the compact destination exactly; never stretch a cached creative.
    final widthPx = (nativeWidth * view.devicePixelRatio).round();
    final request = Yodo1InlinePreloads.load(
      placement,
      backgroundColor: placement.format == AdFormat.native ? '#F5F5F5' : null,
      widthPx: widthPx,
      heightPx: (nativeHeight * view.devicePixelRatio).round(),
    );
    _preloading[placement.id] = request;
    try {
      final ready = await request;
      debugPrint('LauncherInlinePreload [${placement.id}] sdkReady=$ready');
      return ready;
    } finally {
      // Back off from completion, not the beginning of a slow failed request.
      _lastPreloadAttempt[placement.id] = DateTime.now();
      _preloading.remove(placement.id);
    }
  }

  static AppRuntime? get _runtime =>
      sl.isRegistered<AppRuntime>() ? sl<AppRuntime>() : null;

  static AdCoordinator? get _ads {
    final runtime = _runtime;
    final coordinator = runtime?.ads;
    if (coordinator == null) return null;
    return runtime!.adProvider?.health.isOperational ?? false
        ? coordinator
        : null;
  }

  /// Whether onboarding should lay out its native ad slot.
  ///
  /// Requires a configured provider, the remote `onboarding_ads_enabled`
  /// switch and a placement the policy does not rule out. Waits that pass on
  /// their own (initial delay, pacing) still keep the slot: the ad view shows
  /// once they do. Checked when onboarding opens, so no empty space is
  /// reserved in a build or state that can never fill it.
  static bool get onboardingAdAllowed {
    final runtime = _runtime;
    final policy = runtime?.adPolicy;
    if (defaultTargetPlatform != TargetPlatform.android ||
        runtime?.adProvider == null ||
        policy == null) {
      return false;
    }
    if (!runtime!.remoteConfig.current.read(OnboardingPolicyKeys.adsEnabled)) {
      return false;
    }
    final reason = policy
        .evaluate(LauncherAdPlacements.onboardingNative)
        .blockReason;
    return reason == null ||
        reason == AdPolicyBlockReason.initialDelay ||
        reason == AdPolicyBlockReason.frequencyCap;
  }

  /// Whether a mini-app is currently in front. Nothing may show otherwise.
  static bool get insideMiniApp => _insideMiniApp;

  /// Warms the next interstitial. Safe to call when ads are unconfigured.
  static Future<void> preload() async {
    await _runtime?.warmInterstitial();
  }

  /// Shows the mini-app interstitial, if policy and inventory allow it.
  ///
  /// Called as a mini-app opens. The result is deliberately ignored by the
  /// caller: an ad must never delay or block the screen the user asked for.
  static Future<void> onMiniAppOpened(String featureId) async {
    _insideMiniApp = true;
    if (!canShowMiniAppAd) return;
    final ads = _ads;
    if (ads == null) return;
    final result = await ads.show(LauncherAdPlacements.miniAppOpen);
    result.fold(
      onSuccess: (outcome) {
        AppAnalytics.adLifecycle(
          adType: 'interstitial',
          action: 'show',
          result: outcome.wasShown ? 'success' : outcome.status.name,
          source: featureId,
          testAds: false,
        );
        // Whatever happened, line up the next one while nobody is waiting.
        unawaited(preload());
      },
      onFailure: (error) => AppAnalytics.adLifecycle(
        adType: 'interstitial',
        action: 'show',
        result: 'failure',
        source: featureId,
        testAds: false,
        error: error.message,
      ),
    );
  }

  /// Records that the user left the mini-app and is back on the launcher.
  static void onMiniAppClosed() => _insideMiniApp = false;

  /// Shows the app-open ad when the app is resumed **into a mini-app**.
  ///
  /// Resuming onto the home screen shows nothing, which is most resumes: a
  /// launcher is what the Home button opens.
  static Future<void> onResumed() async {
    // Refresh expired unused inventory without adding a splash to Home or to
    // returns from another app. Mounted views retain their own creatives.
    unawaited(prepareInlineAds());
    if (!canShowMiniAppAd) return;
    final ads = _ads;
    if (ads == null) return;
    final result = await ads.show(LauncherAdPlacements.appOpen);
    result.fold(
      onSuccess: (outcome) {
        if (!outcome.wasShown) {
          unawaited(ads.load(LauncherAdPlacements.appOpen));
        }
      },
      onFailure: (_) {},
    );
  }
}
