import 'package:flutter/material.dart';

import 'package:smart_launcher_app/core/services/wallpaper_service.dart';
import 'package:smart_launcher_app/core/utils/app_strings.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/wallpaper_screen.dart';

/// Wallpaper step after set-as-default. Hosts the full wallpaper browser, so
/// picks go through the same preview and home/lock question. Setting a
/// wallpaper moves on by itself; the close button skips the step.
class WallpaperPage extends StatefulWidget {
  const WallpaperPage({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<WallpaperPage> createState() => _WallpaperPageState();
}

class _WallpaperPageState extends State<WallpaperPage> {
  @override
  void initState() {
    super.initState();
    WallpaperService.wallpaperApplied.addListener(widget.onDone);
  }

  @override
  void dispose() {
    WallpaperService.wallpaperApplied.removeListener(widget.onDone);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            height: 48,
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: widget.onDone,
                icon: const Icon(Icons.close),
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            AppStrings.onboardingWallpaperTitle,
            textAlign: TextAlign.center,
            style: text.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
        ),
        const Expanded(child: WallpaperScreen(embedded: true)),
      ],
    );
  }
}
