import 'package:smart_launcher_app/core/config/app_env.dart';

/// Analytics configuration.
///
/// The Mixpanel token now flows through the env-config system: it lives under
/// the `mixpanel_token` key in `env/<flavor>.json` and is loaded at build time
/// via `--dart-define-from-file` (see [AppEnv]). This keeps it out of source
/// and in lockstep with the other per-flavor secrets.
///
/// An empty token cleanly disables Mixpanel (the datasource no-ops on an empty
/// token) rather than crashing. Firebase Analytics needs no token — it
/// authenticates via `google-services.json` / `firebase_options.dart`.
class AnalyticsConfig {
  AnalyticsConfig._();

  static String get mixpanelToken => AppEnv.mixpanelToken;

  /// Whether a Mixpanel token is configured.
  static bool get hasMixpanelToken => AppEnv.mixpanelEnabled;
}
