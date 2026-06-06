import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

class ThemedWallpaperBackground extends StatelessWidget {
  final String path;
  final bool blur;
  final double blurSigma;
  final List<Color> fallbackColors;

  const ThemedWallpaperBackground({
    super.key,
    required this.path,
    this.blur = false,
    this.blurSigma = 12,
    this.fallbackColors = const [Color(0xFF151A1F), Color(0xFF364D45)],
  });

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (path.isNotEmpty && File(path).existsSync()) {
      child = Image.file(
        File(path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else {
      child = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: fallbackColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
    }

    if (!blur) return Positioned.fill(child: child);
    return Positioned.fill(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: child,
      ),
    );
  }
}
