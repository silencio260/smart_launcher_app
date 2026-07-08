import 'package:flutter/material.dart';

import 'package:smart_launcher_app/features/clock/presentation/clock_theme.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/widgets/mini_app_intro_scaffold.dart';

/// One-time intro shown the first time the Clock mini-app is opened. The
/// alarm-related permissions (exact alarm, notifications, full-screen intent,
/// battery) are still requested in-context by the clock screen itself.
class ClockOnboarding extends StatelessWidget {
  const ClockOnboarding({
    super.key,
    required this.onContinue,
    this.onBack,
  });

  final VoidCallback onContinue;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return MiniAppCarouselScaffold(
      featureId: 'alarm_clock',
      accent: clockAccent,
      title: 'Clock',
      slides: const [
        MiniAppIntroSlide(
          icon: Icons.alarm_on_outlined,
          title: 'Create reliable alarms',
          body: 'Set alarms for your routine and tune the system access later.',
          assetPath: 'assets/onboarding/clock_alarm_list.webp',
        ),
        MiniAppIntroSlide(
          icon: Icons.public,
          title: 'Track time zones',
          body: 'Save world clocks and check other cities at a glance.',
          assetPath: 'assets/onboarding/clock_world_clocks.webp',
        ),
        MiniAppIntroSlide(
          icon: Icons.timer_outlined,
          title: 'Focus with timers',
          body: 'Run timers and a stopwatch from the same quiet mini app.',
          assetPath: 'assets/onboarding/clock_timer_stopwatch.webp',
        ),
      ],
      ctaLabel: 'Open Clock',
      onContinue: onContinue,
      onBack: onBack,
    );
  }
}
