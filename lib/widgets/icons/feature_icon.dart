import 'package:flutter/material.dart';

import '../../models/launcher_feature.dart';

class FeatureIcon extends StatelessWidget {
  final String? featureId;
  final String? packageName;
  final double size;

  const FeatureIcon({
    super.key,
    this.featureId,
    this.packageName,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final feature = LauncherFeatureCatalog.fromId(featureId) ??
        (packageName == null
            ? null
            : LauncherFeatureCatalog.fromPackage(packageName!));
    final color = feature?.color ?? Colors.blueGrey;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.225),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: size * 0.18,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: Icon(
        feature?.icon ?? Icons.auto_awesome_outlined,
        color: Colors.white,
        size: size * 0.56,
      ),
    );
  }
}
