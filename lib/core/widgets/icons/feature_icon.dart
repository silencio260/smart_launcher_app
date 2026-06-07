import 'package:flutter/material.dart';

import 'package:smart_launcher_app/core/models/launcher_feature.dart';

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
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        artwork.assetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}
