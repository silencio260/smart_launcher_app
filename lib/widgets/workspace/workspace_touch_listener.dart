import 'package:flutter/material.dart';
import '../../models/launcher_settings.dart';

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
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      onVerticalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -300) onSwipeUp();
        if (v > 300) onSwipeDown();
      },
      child: child,
    );
  }
}
