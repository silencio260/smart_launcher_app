import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_launcher_app/bloc_observer.dart';
import 'package:smart_launcher_app/bootstrap/app_runtime.dart';
import 'package:smart_launcher_app/core/analytics/install_id.dart';
import 'package:smart_launcher_app/firebase_options.dart';
import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/storage/feature_hive_store.dart';
import 'package:smart_launcher_app/features/clock/data/clock_service.dart';
import 'package:smart_launcher_app/features/onboarding/data/onboarding_store.dart';
import 'package:smart_launcher_app/my_app.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    Bloc.observer = const AppBlocObserver();
    initApp();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );
    runApp(const _LauncherBootstrap());
  }, _reportError);
}

void _reportError(Object error, StackTrace stack) {
  debugPrint('Launcher: $error\n$stack');
  if (Firebase.apps.isNotEmpty) {
    unawaited(
      FirebaseCrashlytics.instance
          .recordError(error, stack, fatal: true)
          .catchError((Object error) => debugPrint('Crash reporting: $error')),
    );
  }
}

/// Displays startup immediately and gives failed local preparation a retry.
class _LauncherBootstrap extends StatefulWidget {
  const _LauncherBootstrap();

  @override
  State<_LauncherBootstrap> createState() => _LauncherBootstrapState();
}

class _LauncherBootstrapState extends State<_LauncherBootstrap> {
  AppRuntime? _runtime;
  Object? _error;
  bool _ready = false;
  bool _retrying = false;
  final _previousFlutterError = FlutterError.onError;
  final _previousPlatformError = PlatformDispatcher.instance.onError;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          ).timeout(const Duration(seconds: 20));
        }
        await FirebaseCrashlytics.instance
            .setCrashlyticsCollectionEnabled(!kDebugMode)
            .timeout(const Duration(seconds: 5));
        FlutterError.onError = (details) {
          FlutterError.presentError(details);
          _reportError(details.exception, details.stack ?? StackTrace.current);
        };
        PlatformDispatcher.instance.onError = (error, stack) {
          _reportError(error, stack);
          return true;
        };
      } catch (error, stack) {
        debugPrint('Firebase preparation: $error\n$stack');
      }
      if (!mounted) return;
      await FeatureHiveStore.init();
      await ClockService.init();
      await OnboardingStore.preload();
      if (!mounted) return;
      final installId = InstallId.getOrCreate();
      if (Firebase.apps.isNotEmpty) {
        try {
          await FirebaseCrashlytics.instance
              .setUserIdentifier(installId)
              .timeout(const Duration(seconds: 5));
        } catch (error) {
          debugPrint('Crashlytics identity: $error');
        }
      }
      if (!mounted) return;
      final runtime = AppRuntime(installId: installId);
      _runtime = runtime;
      await runtime.initialize();
      if (!mounted) return;
      sl.registerSingleton<AppRuntime>(runtime);
      setState(() => _ready = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !runtime.scope.isClosed) {
          unawaited(runtime.coordinator.startDeferred());
        }
      });
    } catch (error, stack) {
      _reportError(error, stack);
      await _runtime?.scope.dispose();
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _retry() async {
    if (_retrying) return;
    _retrying = true;
    setState(() => _error = null);
    final previous = _runtime;
    if (previous != null) {
      await previous.scope.dispose();
      previous.dispose();
      _runtime = null;
    }
    if (!mounted) return;
    await _prepare();
    _retrying = false;
  }

  @override
  void dispose() {
    FlutterError.onError = _previousFlutterError;
    PlatformDispatcher.instance.onError = _previousPlatformError;
    if (sl.isRegistered<AppRuntime>() &&
        identical(sl<AppRuntime>(), _runtime)) {
      sl.unregister<AppRuntime>();
    }
    _runtime?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      final replay = _runtime!.replay;
      return replay == null
          ? const MyApp()
          : ListenableBuilder(
            listenable: _runtime!,
            builder: (context, child) => replay.wrap(child!),
            child: const MyApp(),
          );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child:
              _error == null
                  ? const CircularProgressIndicator()
                  : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Could not prepare the launcher. Please retry.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _retry,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
        ),
      ),
    );
  }
}
