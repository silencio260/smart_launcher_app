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
}
