import 'package:smart_launcher_app/bootstrap/app_runtime.dart';
import 'package:smart_launcher_app/container_injector.dart';

/// Reads the remote `launcher_force_default` switch (see `LauncherPolicyKeys`).
abstract final class DefaultLauncherPolicy {
  static AppRuntime? get _runtime =>
      sl.isRegistered<AppRuntime>() ? sl<AppRuntime>() : null;

  /// True when the launcher may only be used as the default home app.
  static bool get forced => _runtime?.forceDefaultLauncher ?? false;

  /// Fires whenever remote configuration changes, so [forced] can be re-read.
  static Stream<Object?> get changes =>
      _runtime?.remoteConfig.changes ?? const Stream<Object?>.empty();
}
