import 'package:flutter/foundation.dart';

/// Runtime-toggled debug flags driven by Developer Options in settings.
class DebugFlags {
  static bool widgetLogs = false;
  static bool widgetDragLogs = false;
  static bool widgetPickerInfo = false;
  static bool drawerPerfLogs = false;
  static bool routeCoverageLogs = false;
  static bool settingsLogs = false;
}

void widgetLog(String message) {
  if (DebugFlags.widgetLogs) debugPrint(message);
}

void dragDropLog(String message) {
  if (DebugFlags.widgetLogs) debugPrint(message);
}

void widgetDragLog(String message) {
  if (DebugFlags.widgetDragLogs) debugPrint(message);
}
