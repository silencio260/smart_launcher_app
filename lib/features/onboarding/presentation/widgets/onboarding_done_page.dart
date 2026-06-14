import 'package:flutter/material.dart';

import 'package:smart_launcher_app/core/utils/app_strings.dart';

/// Brief success confirmation shown once the home role is granted, before the
/// flow auto-continues into the launcher.
class OnboardingDonePage extends StatelessWidget {
  const OnboardingDonePage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Icon(Icons.check_circle, size: 88, color: scheme.onSurface),
          ),
          const SizedBox(height: 28),
          Text(
            AppStrings.onboardingDoneTitle,
            textAlign: TextAlign.center,
            style: text.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.onboardingDoneBody,
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
