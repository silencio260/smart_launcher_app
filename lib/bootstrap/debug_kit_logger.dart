import 'package:flutter/foundation.dart';
import 'package:genrevibes_core/genrevibes_core.dart';
import 'package:smart_launcher_app/core/config/app_env.dart';

/// Prints starter-kit logs to the console.
///
/// The runtime's [KitLogger] is a `RecordingKitLogger` so Kit Lab can show the
/// history, and it forwards here so adopting the recorder did not silence the
/// console output we already relied on while debugging startup.
class DebugKitLogger implements KitLogger {
  /// Creates a console logger.
  const DebugKitLogger();

  @override
  void log(
    KitLogLevel level,
    String message, {
    String? moduleId,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    // Info and below is noise outside development; warnings and errors always
    // matter, including in a release build someone is bug-hunting on device.
    if (!kDebugMode &&
        !AppEnv.developmentMode &&
        level.index < KitLogLevel.warning.index) {
      return;
    }
    final module = moduleId == null ? '' : ' [$moduleId]';
    final extra = fields.isEmpty ? '' : ' $fields';
    debugPrint('kit/${level.name}$module: $message$extra');
    if (error != null) debugPrint('kit/${level.name}$module: error: $error');
  }
}

