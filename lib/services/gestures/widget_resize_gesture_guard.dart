import 'package:flutter/foundation.dart';

class WidgetResizeGestureGuard {
  WidgetResizeGestureGuard._();

  static int _activePointers = 0;
  static final ValueNotifier<bool> isResizingNotifier =
      ValueNotifier<bool>(false);

  static bool get isResizing => _activePointers > 0;

  static void begin() {
    _activePointers += 1;
    isResizingNotifier.value = isResizing;
  }

  static void end() {
    if (_activePointers == 0) return;
    _activePointers -= 1;
    isResizingNotifier.value = isResizing;
  }

  static void reset() {
    _activePointers = 0;
    isResizingNotifier.value = false;
  }
}
