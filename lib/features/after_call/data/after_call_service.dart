import 'package:flutter/services.dart';

/// Thin Dart wrapper over the native `after_call` channel.
///
/// The after-call card itself is drawn natively (over the dialer) — Dart's only
/// jobs are to arm/disarm the call listener with the feature toggle and to handle
/// the app-specific overlay actions (vault, note) that bounce back into the app.
class AfterCallService {
  AfterCallService._();

  static const _channel =
      MethodChannel('com.genrevibes.smartlauncher/after_call');

  /// Enables/disables the manifest call-state receiver. While off, nothing
  /// listens for calls.
  static Future<void> setEnabled(bool enabled) =>
      _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});

  static Future<bool> isEnabled() async =>
      await _channel.invokeMethod<bool>('isEnabled') ?? false;

  /// Pulls the action chosen on the overlay (the tap brings the app forward).
  /// Returns null when there's nothing pending. Call on launch and on resume.
  static Future<String?> consumePendingAction() =>
      _channel.invokeMethod<String>('consumePendingAction');

  /// Debug-only: raises the after-call card immediately, without a real call,
  /// so the overlay can be seen and exercised on demand. Needs the overlay grant
  /// just like the real flow.
  static Future<void> showOverlayNow() =>
      _channel.invokeMethod<void>('showOverlayNow');
}
