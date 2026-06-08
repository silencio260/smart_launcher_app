import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Thin wrapper over Crashlytics custom keys + breadcrumb logs so a crash report
/// carries the app's state and the trail of actions leading up to it.
///
/// All values MUST be non-PII: no third-party package names, no search text, no
/// file/media names, no credentials. Keep them to enums, counts, and flags.
class CrashContext {
  CrashContext._();

  static FirebaseCrashlytics get _c => FirebaseCrashlytics.instance;

  // --- Custom keys (E2): current app state attached to every report. ---

  static void setActiveScreen(String screen) =>
      _c.setCustomKey('active_screen', screen);

  /// Set when entering one of our mini-apps; cleared (empty) on exit.
  static void setActiveMiniApp(String? miniApp) =>
      _c.setCustomKey('active_mini_app', miniApp ?? '');

  static void setString(String key, String value) =>
      _c.setCustomKey(key, value);

  static void setBool(String key, bool value) => _c.setCustomKey(key, value);

  static void setInt(String key, int value) => _c.setCustomKey(key, value);

  // --- Breadcrumbs (E3): terse trail of recent actions. ---

  static void log(String message) => _c.log(message);
}
