import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_launcher_app/bloc_observer.dart';
import 'package:smart_launcher_app/firebase_options.dart';
import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/storage/feature_hive_store.dart';
import 'package:smart_launcher_app/features/clock/data/clock_service.dart';
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));
    runApp(const MyApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}
