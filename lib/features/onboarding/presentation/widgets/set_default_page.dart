import 'package:flutter/material.dart';

import 'package:smart_launcher_app/core/utils/app_strings.dart';

/// Second onboarding page: the nudged, skippable home-role request.
class SetDefaultPage extends StatelessWidget {
  const SetDefaultPage({
    super.key,
    required this.requestInFlight,
    required this.onSetDefault,
    required this.onNotNow,
    required this.onBack,
  });

  final bool requestInFlight;
  final VoidCallback onSetDefault;
  final VoidCallback onNotNow;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 48,
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: requestInFlight ? null : onBack,
                icon: const Icon(Icons.arrow_back),
                color: scheme.onSurface,
              ),
            ),
          ),
          const Spacer(),
          Center(
            child: Container(
              width: 148,
              height: 148,
              decoration: BoxDecoration(
                color: scheme.inverseSurface,
                borderRadius: BorderRadius.circular(36),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.18),
                    blurRadius: 40,
                    offset: const Offset(0, 22),
                  ),
                ],
              ),
              child: Icon(
                Icons.home_rounded,
                size: 76,
                color: scheme.onInverseSurface,
              ),
            ),
          ),
          const SizedBox(height: 36),
          Text(
            AppStrings.onboardingDefaultTitle,
            textAlign: TextAlign.center,
            style: text.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            AppStrings.onboardingDefaultBody,
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.touch_app_outlined,
                    size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppStrings.onboardingDefaultHint,
                    style: text.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(flex: 2),
          FilledButton(
            onPressed: requestInFlight ? null : onSetDefault,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: requestInFlight
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onPrimary,
                    ),
                  )
                : const Text(AppStrings.onboardingSetDefault),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: requestInFlight ? null : onNotNow,
            child: const Text(AppStrings.onboardingNotNow),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
