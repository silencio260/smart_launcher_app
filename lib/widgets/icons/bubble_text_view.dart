import 'dart:math' as math;
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hasHeight = constraints.hasBoundedHeight;
            final maxHeight =
                hasHeight ? constraints.maxHeight : double.infinity;
            final canShowLabel = showLabel && (!hasHeight || maxHeight >= 32);
            final labelHeight = canShowLabel ? labelSize + 2 : 0;
            final availableIconHeight =
                hasHeight ? math.max(0.0, maxHeight - labelHeight) : iconSize;
            final fittedIconSize = math.min(iconSize, availableIconHeight);
            final label = SizedBox(
              width: fittedIconSize + 8,
              child: Text(
                app.name,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: labelSize,
                  height: 1.0,
                  shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            );

            return ClipRect(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: fittedIconSize,
                    height: fittedIconSize,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ShapedIcon(
                          iconBytes: app.icon,
                          shape: iconShape,
                          size: fittedIconSize,
                        ),
                        if (badgeCount > 0 && fittedIconSize > 0)
                          DotRenderer(
                            count: badgeCount,
                            iconSize: fittedIconSize,
                          ),
                      ],
                    ),
                  ),
                  if (canShowLabel) ...[
                    const SizedBox(height: 2),
                    if (hasHeight) Flexible(child: label) else label,
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
