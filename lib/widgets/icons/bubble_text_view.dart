import 'package:flutter/material.dart';
import '../../models/app_info.dart';
import 'shaped_icon.dart';
import 'dot_renderer.dart';

class BubbleTextView extends StatelessWidget {
  final AppInfo app;
  final double iconSize;
  final bool showLabel;
  final double labelSize;
  final bool isDragging;
  final int badgeCount;
  final String iconShape;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const BubbleTextView({
    super.key,
    required this.app,
    this.iconSize = 56,
    this.showLabel = true,
    this.labelSize = 12,
    this.isDragging = false,
    this.badgeCount = 0,
    this.iconShape = 'squircle',
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Opacity(
        opacity: isDragging ? 0.4 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                ShapedIcon(
                    iconBytes: app.icon, shape: iconShape, size: iconSize),
                if (badgeCount > 0)
                  DotRenderer(count: badgeCount, iconSize: iconSize),
              ],
            ),
            if (showLabel) ...[
              const SizedBox(height: 2),
              SizedBox(
                width: iconSize + 8,
                child: Text(
                  app.name,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: labelSize,
                    height: 1.0,
                    shadows: const [
                      Shadow(blurRadius: 4, color: Colors.black54)
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
