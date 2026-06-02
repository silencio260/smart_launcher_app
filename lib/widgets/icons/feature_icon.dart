import 'package:flutter/material.dart';

import '../../models/launcher_feature.dart';

class FeatureIcon extends StatelessWidget {
  final String? featureId;
  final String? packageName;
  final String? componentName;
  final double size;

  const FeatureIcon({
    super.key,
    this.featureId,
    this.packageName,
    this.componentName,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final artwork = LauncherFeatureCatalog.artworkForComponent(componentName) ??
        LauncherFeatureCatalog.artworkForId(featureId) ??
        (packageName == null
            ? null
            : LauncherFeatureCatalog.fromPackage(packageName!) == null
                ? null
                : LauncherFeatureCatalog.artworkForId(
                    LauncherFeatureCatalog.idForPackage(packageName!),
                  )) ??
        LauncherFeatureCatalog.appHiderArtwork;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: artwork.color,
        borderRadius: BorderRadius.circular(size * 0.225),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: size * 0.18,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.06),
        child: Image.asset(
          artwork.assetPath,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
