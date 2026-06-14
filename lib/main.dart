import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:genrevibes_starter_kit/starter_kit.dart';
import 'package:smart_launcher_app/bloc_observer.dart';
import 'package:smart_launcher_app/core/ads/test_ads_config.dart';
import 'package:smart_launcher_app/core/analytics/analytics_config.dart';
import 'package:smart_launcher_app/core/analytics/install_id.dart';
import 'package:smart_launcher_app/firebase_options.dart';
import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/storage/feature_hive_store.dart';
import 'package:smart_launcher_app/features/clock/data/clock_service.dart';
import 'package:smart_launcher_app/features/onboarding/data/onboarding_store.dart';
import 'package:smart_launcher_app/my_app.dart';

Future<void> main() async {
  // runZonedGuarded catches uncaught async/Dart errors that the framework's
  // own hooks miss, funnelling them into Crashlytics alongside everything else.
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final app = await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('🔥 Firebase initialized: ${app.name} '
          '(project: ${app.options.projectId})');
    } catch (e, st) {
      debugPrint('🔥 Firebase initialization FAILED: $e');
      debugPrint('$st');
    }

    // Disable Crashlytics collection in debug so local dev crashes don't
    // pollute the dashboard; real (release) crashes are still reported.
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);

    // Flutter framework errors (build/layout/paint) -> Crashlytics.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    // Low-level platform/engine errors -> Crashlytics.
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    Bloc.observer = const AppBlocObserver();
    initApp();
    await FeatureHiveStore.init();
    await ClockService.init();

    // Warm the onboarding-completion flag so the home gate can route to the
    // first-run flow or the launcher synchronously (no first-frame flash).
    await OnboardingStore.preload();

    // Anonymous, stable install id — groups crashes/sessions per install and
    // seeds Mixpanel session replay. Set on Crashlytics immediately so even an
    // early crash is attributable.
    final installId = InstallId.getOrCreate();
    await FirebaseCrashlytics.instance.setUserIdentifier(installId);

    // Bring up the shared analytics stack: Firebase + Mixpanel fan-out.
    // (Crashlytics stays wired directly here in main — not routed through the
    // kit — to avoid double-reporting crashes.)
    await StarterKit.initialize(
      mixpanelDataSource: MixpanelRemoteDataSourceImpl(),
      analyticsUserId: installId,
      mixpanelToken: AnalyticsConfig.mixpanelToken,
      mixpanelDistinctId: installId,
    );
    final testAdsConfig = TestAdsConfig.fromAppEnv();
    if (testAdsConfig != null) {
      StarterKit.adsBloc.add(AdsInitialize(config: testAdsConfig));
    }

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));

    // Mixpanel session replay binds to the widget tree. With no token
    // configured the wrapper is a transparent passthrough (replay disabled).
    runApp(
      AnalyticsConfig.hasMixpanelToken
          ? StarterKit.mixpanelWrapper(
              token: AnalyticsConfig.mixpanelToken,
              distinctId: installId,
              child: const MyApp(),
            )
          : const MyApp(),
    );
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}
