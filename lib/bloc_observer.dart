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
    super.onError(bloc, error, stackTrace);
  }
}
