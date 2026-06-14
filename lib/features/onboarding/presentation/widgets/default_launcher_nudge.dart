import 'package:flutter/material.dart';

import 'package:smart_launcher_app/core/utils/app_strings.dart';

/// Dismissible "set as default home app" pill shown on the launcher after the
/// user skipped that step during onboarding. Rendered inside the home screen's
/// root overlay as a thin top band only — it deliberately does NOT cover the
/// workspace, so first-swipe-to-open-drawer keeps working.
class DefaultLauncherNudge extends StatelessWidget {
  const DefaultLauncherNudge({
    super.key,
    required this.onTap,
    required this.onDismiss,
  });

  final VoidCallback onTap;
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
        child: Transform.translate(offset: Offset(0, (1 - t) * -12), child: child),
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
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(28),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.home_outlined,
                            size: 20, color: scheme.onSurface),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            AppStrings.defaultNudgeLabel,
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
                tooltip: AppStrings.onboardingNotNow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
