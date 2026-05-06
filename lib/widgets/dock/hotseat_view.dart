import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/app_info.dart';
import '../../models/launcher_settings.dart';
import '../icons/bubble_text_view.dart';

class HotseatView extends StatelessWidget {
  final List<AppInfo> apps;
  final LauncherSettings settings;
  final Map<String, int> badgeCounts;
  final VoidCallback onSwipeUp;
  final void Function(AppInfo app) onAppTap;
  final void Function(AppInfo app) onAppLongPress;

  const HotseatView({
    super.key,
    required this.apps,
    required this.settings,
    required this.badgeCounts,
    required this.onSwipeUp,
    required this.onAppTap,
    required this.onAppLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (!settings.showDock || apps.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) onSwipeUp();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: settings.dockShowBackground
                  ? settings.dockBackgroundColor
                      .withValues(alpha: settings.dockBackgroundOpacity)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: apps.take(settings.dockSize).map((app) {
                return BubbleTextView(
                  app: app,
                  iconSize: settings.dockIconSize,
                  showLabel: settings.showDockLabels,
                  iconShape: settings.iconShape,
                  badgeCount: badgeCounts[app.packageName] ?? 0,
                  onTap: () => onAppTap(app),
                  onLongPress: () => onAppLongPress(app),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
