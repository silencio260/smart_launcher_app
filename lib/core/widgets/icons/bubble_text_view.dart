import 'package:flutter/material.dart';
import 'package:smart_launcher_app/core/models/app_info.dart';
import 'package:smart_launcher_app/core/widgets/icons/feature_icon.dart';
import 'package:smart_launcher_app/core/widgets/icons/shaped_icon.dart';
import 'package:smart_launcher_app/core/widgets/icons/dot_renderer.dart';

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
    final iconStack = SizedBox(
      width: iconSize,
      height: iconSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (app.isInternalFeature)
            FeatureIcon(
              featureId: app.launcherFeatureId,
              packageName: app.packageName,
              componentName: app.appComponentName,
              size: iconSize,
            )
          else
            ShapedIcon(
              iconBytes: app.icon,
              iconPath: app.iconPath,
              shape: iconShape,
              size: iconSize,
              cacheKey: app.isInternalFeature
                  ? app.appComponentName
                  : app.packageName,
            ),
          if (badgeCount > 0)
            DotRenderer(
              count: badgeCount,
              iconSize: iconSize,
            ),
        ],
      ),
    );

    Widget body;
    if (showLabel) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconStack,
          const SizedBox(height: 2),
          SizedBox(
            width: iconSize + 8,
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
          ),
        ],
      );
    } else {
      body = iconStack;
    }

    Widget child = body;
    if (isDragging) {
      child = Opacity(opacity: 0.4, child: child);
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: child,
    );
  }
}
