import 'package:flutter/material.dart';

import 'package:smart_launcher_app/features/onboarding/presentation/widgets/mini_app_intro_scaffold.dart';

/// One-time intro shown the first time App Hider is opened, before its lock /
/// setup screen.
class AppHiderOnboarding extends StatelessWidget {
  const AppHiderOnboarding({
    super.key,
    required this.onContinue,
    this.onBack,
  });

  final VoidCallback onContinue;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return MiniAppCarouselScaffold(
      featureId: 'app_hider',
      accent: const Color(0xFF8B6CFF),
      title: 'App Hider',
      slides: const [
        MiniAppIntroSlide(
          icon: Icons.grid_off_outlined,
          title: 'Hide apps from view',
          body: 'Move private apps out of the drawer and launcher search.',
          assetPath: 'assets/onboarding/app_hider_hide_apps.png',
        ),
        MiniAppIntroSlide(
          icon: Icons.theater_comedy_outlined,
          title: 'Disguise the entry',
          body:
              'Use a harmless-looking icon when you want the hider tucked away.',
          assetPath: 'assets/onboarding/app_hider_disguise_icon.png',
        ),
        MiniAppIntroSlide(
          icon: Icons.lock_open_outlined,
          title: 'Reveal only after unlock',
          body: 'Open hidden apps after your PIN, pattern, or fingerprint.',
          assetPath: 'assets/onboarding/app_hider_secure_reveal.png',
        ),
      ],
      ctaLabel: 'Set up App Hider',
      onContinue: onContinue,
      onBack: onBack,
    );
  }
}
