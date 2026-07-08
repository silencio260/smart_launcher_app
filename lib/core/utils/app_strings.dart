/// App-wide, user-facing strings shared across multiple features.
///
/// Per the localization strategy in ARCHITECTURE_ANALYSIS.md, no user-facing
/// text should be hardcoded in UI. Shared text lives here; feature-specific text
/// lives in `features/{feature}/presentation/l10n/{feature}_strings.dart`. These
/// are plain `static const` today and are the migration point for `.arb`-based
/// i18n later (no code generation required to introduce them).
class AppStrings {
  AppStrings._();

  static const String appName = 'Smart Launcher';

  // --- Onboarding: welcome ---
  static const String onboardingWelcomeTitle = appName;
  static const String onboardingWelcomeBody =
      'A faster, cleaner home screen with search, widgets, and private tools '
      'right where you need them.';
  static const String onboardingGetStarted = 'Get started';

  // --- Onboarding: search / organization ---
  static const String onboardingSearchTitle = 'Find everything fast';
  static const String onboardingSearchBody =
      'Search apps, jump into tools, and keep your phone organized without '
      'digging through clutter.';
  static const String onboardingContinue = 'Continue';

  // --- Onboarding: launcher style ---
  static const String onboardingStyleTitle = 'Pick your launcher style';
  static const String onboardingStyleBody =
      'Start with Smart Launcher, an iOS-style layout, or a quiet minimal home '
      'screen. You can change this later.';
  static const String onboardingStyleSmart = 'Smart';
  static const String onboardingStyleSmartBody =
      'Widgets, dock, search, and organized pages.';
  static const String onboardingStyleIos = 'iOS';
  static const String onboardingStyleIosBody =
      'Familiar icon grid, dock, and app library feel.';
  static const String onboardingStyleMinimal = 'Minimal';
  static const String onboardingStyleMinimalBody =
      'A clean text-first home screen with less noise.';

  // --- Onboarding: set as default ---
  static const String onboardingDefaultTitle = 'Make this your home screen';
  static const String onboardingDefaultBody =
      'Set Smart Launcher as your default so this experience opens when you '
      'press the home button.';
  static const String onboardingDefaultHint =
      'You can change this anytime in Settings.';
  static const String onboardingSetDefault = 'Set as default';
  static const String onboardingNotNow = 'Not now';

  // --- Onboarding: confirmation ---
  static const String onboardingDoneTitle = "You're all set";
  static const String onboardingDoneBody =
      'Smart Launcher is now your home screen.';

  // --- Home-screen "set as default" nudge ---
  static const String defaultNudgeLabel = 'Set as default home app';
}
