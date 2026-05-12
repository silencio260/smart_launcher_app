import 'package:flutter/material.dart';
import '../../models/launcher_settings.dart';
import '../../services/gestures/widget_resize_gesture_guard.dart';

class WorkspaceTouchListener extends StatelessWidget {
  final Widget child;
  final LauncherSettings settings;
  final VoidCallback onSwipeUp;
  final VoidCallback onSwipeDown;
  final VoidCallback onDoubleTap;
  final VoidCallback onLongPress;

  const WorkspaceTouchListener({
    super.key,
    required this.child,
    required this.settings,
    required this.onSwipeUp,
    required this.onSwipeDown,
    required this.onDoubleTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () {
        if (WidgetResizeGestureGuard.isResizing) return;
        onDoubleTap();
      },
      onLongPress: () {
        if (WidgetResizeGestureGuard.isResizing) return;
        onLongPress();
      },
      onVerticalDragEnd: (details) {
        if (WidgetResizeGestureGuard.isResizing) return;
        final v = details.primaryVelocity ?? 0;
        if (v < -300) onSwipeUp();
        if (v > 300) onSwipeDown();
      },
      child: child,
    );
  }
}
