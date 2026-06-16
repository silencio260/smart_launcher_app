import 'package:flutter/material.dart';

/// Full-screen "setting up" cover shown on a genuine cold/fresh start while the
/// installed-apps list is being enumerated and every icon rasterized for the
/// first time.
///
/// On a fresh install there is no app snapshot and the native icon caches are
/// empty, so the first enumeration must load + rasterize + PNG-encode an icon
/// for every launcher activity before anything can paint — a few seconds during
/// which the home screen would otherwise sit empty. This view fills that gap.
///
/// It is gated by the home screen on `AppsState.loading && apps.isEmpty`, which
/// is only true during that first uncached pass: every later launch emits the
/// cached snapshot immediately (apps non-empty), so this never flashes on a
/// warm start.
class LauncherInitializingView extends StatelessWidget {
  const LauncherInitializingView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Setting up your launcher',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Getting your apps ready…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
