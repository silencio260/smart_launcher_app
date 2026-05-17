import 'package:flutter/material.dart';
import '../../models/launcher_settings.dart';
import '../../services/drag/drag_controller.dart';
import '../../services/gestures/widget_resize_gesture_guard.dart';

class WorkspaceTouchListener extends StatelessWidget {
  final Widget child;
  final LauncherSettings settings;
  final DragController dragController;
  final VoidCallback onSwipeUp;
  final VoidCallback onSwipeDown;
  final VoidCallback onDoubleTap;
  final VoidCallback onLongPress;

  const WorkspaceTouchListener({
    super.key,
    required this.child,
    required this.settings,
    required this.dragController,
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
        if (dragController.isDragging) return;
        onDoubleTap();
      },
      onLongPress: () {
        if (WidgetResizeGestureGuard.isResizing) return;
        // Defer one frame so a child LongPressDraggable that fires at the
        // same threshold can mark the drag as active before we decide.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (dragController.isDragging) return;
          if (WidgetResizeGestureGuard.isResizing) return;
          onLongPress();
        });
      },
      onVerticalDragEnd: (details) {
        if (WidgetResizeGestureGuard.isResizing) return;
        if (dragController.isDragging) return;
        final v = details.primaryVelocity ?? 0;
        if (v < -300) onSwipeUp();
        if (v > 300) onSwipeDown();
      },
      child: child,
    );
  }
}
