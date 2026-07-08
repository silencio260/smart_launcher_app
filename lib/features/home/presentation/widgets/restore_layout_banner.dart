import 'package:flutter/material.dart';

/// Top band offering to rebuild the default home layout, shown only in the rare
/// case where the first-run "Setting up your launcher" failsafe (10s) fired
/// before the layout finished seeding. Mirrors [DefaultLauncherNudge]'s look and
/// placement so it reads as a sibling action directly under the set-as-default
/// pill, and — like it — never covers the workspace.
class RestoreLayoutBanner extends StatelessWidget {
  const RestoreLayoutBanner({
    super.key,
    required this.onRestore,
    required this.onDismiss,
  });

  final VoidCallback onRestore;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, (1 - t) * -12), child: child),
      ),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onRestore,
                  borderRadius: BorderRadius.circular(28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.grid_view_outlined,
                            size: 20, color: scheme.onSurface),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Restore home screen layout',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        Icon(Icons.arrow_forward,
                            size: 18, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close, size: 18),
                color: scheme.onSurfaceVariant,
                tooltip: 'Dismiss',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
