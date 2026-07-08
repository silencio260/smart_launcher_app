import 'package:flutter/material.dart';

import 'package:smart_launcher_app/features/onboarding/presentation/widgets/mini_app_intro_scaffold.dart';

/// One-time intro shown the first time App Lock is opened, before the lock /
/// setup screen. Permissions (usage access + overlay) are still requested
/// in-context by the existing protection guide, not here.
class AppLockOnboarding extends StatelessWidget {
  const AppLockOnboarding({
    super.key,
    required this.onContinue,
    this.onBack,
  });

  final VoidCallback onContinue;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return MiniAppCarouselScaffold(
      featureId: 'app_locker',
      accent: const Color(0xFFFF6B5F),
      title: 'App Lock',
      slides: const [
        MiniAppIntroSlide(
          icon: Icons.checklist_rounded,
          title: 'Choose apps to protect',
          body: 'Pick the apps that should open only after you approve them.',
          assetPath: 'assets/onboarding/app_lock_choose_apps.webp',
        ),
        MiniAppIntroSlide(
          icon: Icons.fingerprint_rounded,
          title: 'Use your unlock style',
          body: 'Set up a PIN, pattern, or fingerprint for quick access.',
          assetPath: 'assets/onboarding/app_lock_unlock_methods.webp',
        ),
        MiniAppIntroSlide(
          icon: Icons.shield_outlined,
          title: 'Keep protection active',
          body: 'Locked apps stay guarded when they are opened from here.',
          assetPath: 'assets/onboarding/app_lock_protection_active.webp',
        ),
      ],
      ctaLabel: 'Set up App Lock',
      onContinue: onContinue,
      onBack: onBack,
    );
  }
}
