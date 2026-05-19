import 'package:flutter/material.dart';
import '../../services/drag/drag_controller.dart';
import '../../models/app_info.dart';
import '../icons/shaped_icon.dart';

class DragView extends StatelessWidget {
  final DragPayload payload;
  final Offset position;
  final String iconShape;

  const DragView({
    super.key,
    required this.payload,
    required this.position,
    this.iconShape = 'squircle',
  });

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    Widget icon;

    if (payload.item is AppInfo) {
      final app = payload.item as AppInfo;
      icon = ShapedIcon(
        iconBytes: app.icon,
        iconPath: app.iconPath,
        shape: iconShape,
        size: size,
        cacheKey: app.packageName,
      );
    } else {
      icon = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.apps, color: Colors.white70, size: 36),
      );
    }

    return Positioned(
      left: position.dx - size / 2,
      top: position.dy - size / 2,
      child: IgnorePointer(
        child: Transform.scale(
          scale: 1.15,
          child: Opacity(
            opacity: 0.85,
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: icon,
            ),
          ),
        ),
      ),
    );
  }
}
