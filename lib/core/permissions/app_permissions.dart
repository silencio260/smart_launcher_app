import 'package:genrevibes_permissions/genrevibes_permissions.dart';
import 'package:smart_launcher_app/bootstrap/app_runtime.dart';
import 'package:smart_launcher_app/container_injector.dart';

/// The launcher's runtime permissions, through the kit's coordinator.
///
/// The coordinator adds what hand-rolled calls kept getting wrong: it never
/// re-prompts a permission that is already usable, it throttles repeat asks,
/// and it reports "the user must change this in Settings" as its own result
/// instead of a plain denial.
///
/// Android special access — usage access, notification listener, overlay,
/// exact alarms, set-as-default — is not a runtime permission and is not here;
/// those stay on `LauncherService`.
abstract final class AppPermissions {
  static PermissionCoordinator? get _coordinator {
    if (!sl.isRegistered<AppRuntime>()) return null;
    final coordinator = sl<AppRuntime>().permissions;
    return coordinator.health.isOperational ? coordinator : null;
  }

  /// Whether every [kinds] permission is usable right now.
  static Future<bool> has(Iterable<PermissionKind> kinds) async {
    final result = await _coordinator?.check(kinds);
    return result?.fold(
          onSuccess: (value) => value.status == PermissionFlowStatus.granted,
          onFailure: (_) => false,
        ) ??
        false;
  }

  /// Asks for [kinds] if needed, and reports what happened.
  ///
  /// Returns null when the runtime is unavailable, which a caller treats the
  /// same as "not granted" rather than as an error worth showing.
  static Future<PermissionFlowResult?> request(
    Iterable<PermissionKind> kinds,
  ) async {
    final result = await _coordinator?.request(kinds);
    return result?.fold(onSuccess: (value) => value, onFailure: (_) => null);
  }

  /// Asks for notifications. True when they are usable afterwards.
  static Future<bool> requestNotifications() async {
    final result = await request(const [PermissionKind.notifications]);
    return result?.status == PermissionFlowStatus.granted;
  }

  /// Whether notifications are usable.
  static Future<bool> hasNotifications() =>
      has(const [PermissionKind.notifications]);

  /// Opens the system settings page for this app, for a permission the user
  /// has permanently denied.
  static Future<void> openSettings() async {
    await _coordinator?.openSettings();
  }
}
