import 'dart:async';

import 'package:genrevibes_ads/genrevibes_ads.dart';
import 'package:smart_launcher_app/bootstrap/app_runtime.dart';
import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/analytics/app_events.dart';

/// Where the launcher is allowed to show an ad.
///
/// Yodo1 MAS keeps one creative per format, so these ids do not create
/// separate inventory; they are how this app's own pacing, remote policy and
/// analytics tell its placements apart.
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
  static const libraryNative = AdPlacement(
    id: 'app_library',
    format: AdFormat.native,
  );
  static const searchNative = AdPlacement(
    id: 'idle_search',
    format: AdFormat.native,
  );

  /// Every placement the app declares, for remote policy and Kit Lab.
  static const all = <AdPlacement>[
    miniAppOpen,
    appOpen,
    miniAppBanner,
    discoverNative,
    drawerNative,
    libraryNative,
    searchNative,
  ];
}

/// The launcher's ad rules.
///
/// Full-screen ads are confined to mini-apps. Inline native ads have their own
/// explicitly selected slots on Discover, the drawer, App Library and idle
/// search. Regular workspace pages and folder views remain ad-free.
///
/// Pacing, intervals and the master switch come from remote config through
/// `AdPolicyController`; this class only decides *where* a request is even
/// considered.
abstract final class LauncherAds {
  static bool _insideMiniApp = false;

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

  /// Whether a mini-app is currently in front. Nothing may show otherwise.
  static bool get insideMiniApp => _insideMiniApp;

  /// Warms the next interstitial. Safe to call when ads are unconfigured.
  static Future<void> preload() async {
    final ads = _ads;
    if (ads == null) return;
    await ads.load(LauncherAdPlacements.miniAppOpen);
  }

  /// Shows the mini-app interstitial, if policy and inventory allow it.
  ///
  /// Called as a mini-app opens. The result is deliberately ignored by the
  /// caller: an ad must never delay or block the screen the user asked for.
  static Future<void> onMiniAppOpened(String featureId) async {
    _insideMiniApp = true;
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
        unawaited(ads.load(LauncherAdPlacements.miniAppOpen));
      },
      onFailure:
          (error) => AppAnalytics.adLifecycle(
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
    if (!_insideMiniApp) return;
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
