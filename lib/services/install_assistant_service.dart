import 'package:flutter/services.dart';

/// Thin Dart wrapper over the native `install_assistant` channel.
///
/// The Install/Uninstall Assistant card is drawn natively (a system overlay over
/// whatever is on screen), so Dart's only jobs are to arm/disarm the package
/// detector with the feature toggle and to drain the actions chosen on the card
/// (add-to-home, hide, cleanup, disable) when the launcher next resumes.
class InstallAssistantService {
  InstallAssistantService._();

  static const _channel =
      MethodChannel('com.genrevibes.smartlauncher/install_assistant');

  /// Enables/disables the app-scoped package detector. While off, nothing
  /// listens for installs/uninstalls.
  static Future<void> setEnabled(bool enabled) =>
      _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});

  static Future<bool> isEnabled() async =>
      await _channel.invokeMethod<bool>('isEnabled') ?? false;

  /// Pulls the action chosen on the overlay. Returns null when there's nothing
  /// pending. Call on launch and on resume. Format: `add_home:<pkg>`,
  /// `hide:<pkg>`, `cleanup:<pkg>`, or `disable`.
  static Future<String?> consumePendingAction() =>
      _channel.invokeMethod<String>('consumePendingAction');

  /// Debug-only: raise the assistant card immediately for [packageName] without
  /// a real install. Needs the overlay grant just like the real flow.
  static Future<void> showOverlayNow(String packageName,
          {bool removed = false}) =>
      _channel.invokeMethod<void>(
          'showOverlayNow', {'packageName': packageName, 'removed': removed});
}
