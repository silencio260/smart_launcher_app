class WidgetResizeGestureGuard {
  WidgetResizeGestureGuard._();

  static int _activePointers = 0;

  static bool get isResizing => _activePointers > 0;

  static void begin() {
    _activePointers += 1;
  }

  static void end() {
    if (_activePointers == 0) return;
    _activePointers -= 1;
  }

  static void reset() {
    _activePointers = 0;
  }
}
