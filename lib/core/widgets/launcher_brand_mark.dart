import 'package:flutter/material.dart';

/// The same artwork shipped as the Android launcher icon, not a placeholder.
class LauncherBrandMark extends StatelessWidget {
  const LauncherBrandMark({super.key, this.size = 112});

  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.21),
    child: Image.asset(
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
    ),
  );
}
