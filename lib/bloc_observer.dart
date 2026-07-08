import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Global observer for all Blocs/Cubits.
///
/// Wired in `main.dart` via `Bloc.observer = AppBlocObserver();`.
class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  /// Cubits whose transitions are worth a Crashlytics breadcrumb. Kept short so
  /// the breadcrumb buffer reflects meaningful navigation/state, not chatter.
  static const _breadcrumbCubits = {
    'LauncherCubit',
    'WorkspaceCubit',
    'SearchCubit',
    'AppsCubit',
    'SettingsCubit',
    'LauncherFeatureSettingsCubit',
  };

  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    final line =
        '[Bloc] ${bloc.runtimeType} -> ${change.nextState.runtimeType}';
    if (kDebugMode) {
      debugPrint(line);
    }
    // Leave a release breadcrumb for important cubits so a later crash report
    // shows the trail of states that preceded it.
    if (_breadcrumbCubits.contains(bloc.runtimeType.toString())) {
      FirebaseCrashlytics.instance.log(line);
    }
  }

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('[Bloc] ${bloc.runtimeType} ERROR: $error');
    }
    // Report Cubit/Bloc exceptions as non-fatals (collection is gated to
    // release builds via setCrashlyticsCollectionEnabled in main()).
    // NOTE: single capture path — do NOT also route through StarterKit.analytics
    // (the kit's Firebase datasource calls the same Crashlytics API → dupes).
    FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      reason: '${bloc.runtimeType} error',
      fatal: false,
    );
    super.onError(bloc, error, stackTrace);
  }
}
