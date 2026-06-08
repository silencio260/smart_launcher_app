import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Global observer for all Blocs/Cubits.
///
/// Wired in `main.dart` via `Bloc.observer = AppBlocObserver();`. Logs are
/// gated behind [kDebugMode] so release builds stay silent.
class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    if (kDebugMode) {
      debugPrint('[Bloc] ${bloc.runtimeType} -> ${change.nextState.runtimeType}');
    }
  }

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('[Bloc] ${bloc.runtimeType} ERROR: $error');
    }
    // Report Cubit/Bloc exceptions as non-fatals (collection is gated to
    // release builds via setCrashlyticsCollectionEnabled in main()).
    FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      reason: '${bloc.runtimeType} error',
      fatal: false,
    );
    super.onError(bloc, error, stackTrace);
  }
}
