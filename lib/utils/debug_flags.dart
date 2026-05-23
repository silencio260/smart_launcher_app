import 'package:flutter/foundation.dart';

/// Runtime-toggled debug flags driven by Developer Options in settings.
class DebugFlags {
  static bool widgetLogs = false;
  static bool widgetPickerInfo = false;
  static bool drawerPerfLogs = false;
}

void widgetLog(String message) {
  if (DebugFlags.widgetLogs) debugPrint(message);
}
