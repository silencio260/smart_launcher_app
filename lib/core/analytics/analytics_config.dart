/// Analytics configuration.
///
/// The Mixpanel project token. Prefer providing it at build time via
/// `--dart-define=MIXPANEL_TOKEN=xxxx` (keeps the token out of source/VCS).
/// The fallback constant is empty so a missing token cleanly disables Mixpanel
/// (the datasource no-ops on an empty token) rather than crashing.
class AnalyticsConfig {
  AnalyticsConfig._();

  static const String mixpanelToken =
      String.fromEnvironment('MIXPANEL_TOKEN', defaultValue: '');

  /// Whether a Mixpanel token is configured.
  static bool get hasMixpanelToken => mixpanelToken.isNotEmpty;
}
