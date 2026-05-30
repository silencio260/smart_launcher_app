import 'dart:io';

import 'package:flutter/material.dart';
import '../models/app_info.dart';
import '../models/launcher_feature.dart';
import '../services/feature_launch_dispatcher.dart';
import '../services/launcher_service.dart';
import 'icons/feature_icon.dart';

class AppIcon extends StatelessWidget {
  final AppInfo app;
  final double iconSize;
  final double labelFontSize;
  final bool showLabel;
  final VoidCallback? onLongPress;

  const AppIcon({
    super.key,
    required this.app,
    this.iconSize = 52,
    this.labelFontSize = 11,
    this.showLabel = true,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FeatureLaunchDispatcher.launch(context, app),
      onLongPress: onLongPress ?? () => _showAppMenu(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildIcon(),
          if (showLabel) ...[
            const SizedBox(height: 4),
            Text(
              app.name,
              style: TextStyle(
                color: Colors.white,
                fontSize: labelFontSize,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIcon() {
    if (app.isInternalFeature) {
      return FeatureIcon(
        featureId: app.launcherFeatureId,
        packageName: app.packageName,
        size: iconSize,
      );
    }
    final iconPath = app.iconPath;
    if (iconPath != null && iconPath.isNotEmpty) {
      return Image.file(
        File(iconPath),
        width: iconSize,
        height: iconSize,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) {
          if (app.icon != null) {
            return Image.memory(
              app.icon!,
              width: iconSize,
              height: iconSize,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _fallbackIcon(),
            );
          }
          return _fallbackIcon();
        },
      );
    }
    if (app.icon != null) {
      return Image.memory(
        app.icon!,
        width: iconSize,
        height: iconSize,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _fallbackIcon(),
      );
    }
    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return Container(
      width: iconSize,
      height: iconSize,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.android, color: Colors.white70),
    );
  }

  void _showAppMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AppMenu(app: app),
    );
  }
}

class _AppMenu extends StatelessWidget {
  final AppInfo app;
  const _AppMenu({required this.app});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900]!.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            app.name,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white12),
          _menuItem(context, Icons.info_outline, 'App info', () {
            Navigator.pop(context);
            final featureId = app.launcherFeatureId ??
                LauncherFeatureCatalog.idForPackage(app.packageName);
            if (featureId != null) {
              FeatureLaunchDispatcher.openFeature(context, featureId);
            } else {
              LauncherService.openAppSettings(app.packageName);
            }
          }),
          if (!app.isInternalFeature)
            _menuItem(context, Icons.delete_outline, 'Uninstall', () {
              Navigator.pop(context);
              LauncherService.uninstallApp(app.packageName);
            }),
          _menuItem(
              context, Icons.close, 'Cancel', () => Navigator.pop(context)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _menuItem(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }
}
