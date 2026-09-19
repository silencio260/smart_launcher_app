/// Compile-time environment configuration.
///
/// Per the GenRevibes env-config convention, every build loads one of the
/// `env/*.json` files via `--dart-define-from-file` (wired in `.run/` and
/// `.vscode/launch.json`). This class is the single typed accessor for those
/// values — feature code reads `AppEnv.x`, never `String.fromEnvironment`
/// scattered around.
///
/// Values are `const`: they are baked in at compile time, so there is no
/// runtime cost and an unset key falls back to the declared default. A missing
/// `env/<flavor>.json` simply means every value is its default (e.g. empty
/// strings disable the matching SDK rather than crashing).
class AppEnv {
  AppEnv._();

  // --- Build flavor flags ---

  static const bool foundersVersion =
      bool.fromEnvironment('founders_version', defaultValue: false);
  static const bool specialVersionMode =
      bool.fromEnvironment('special_version_mode', defaultValue: false);

  /// Dev builds (dev.json / special_dev.json) set this true; release.json
  /// leaves it false. Distinct from `kDebugMode` — a profile/release binary
  /// can still be flagged a development build via the env file.
  static const bool developmentMode =
      bool.fromEnvironment('development_mode', defaultValue: false);

  // --- Firebase (env mirrors firebase_options.dart; kept for parity) ---

  static const String firebaseApiKeyAndroid =
      String.fromEnvironment('firebase_api_key_android');
  static const String firebaseApiKeyIos =
      String.fromEnvironment('firebase_api_key_ios');

  // --- Backend ---

  static const String cloudFunctionsBaseUrl =
      String.fromEnvironment('cloud_functions_base_url');

  // --- Ads (AdMob unit IDs) ---

  static const String bannerAdId = String.fromEnvironment('banner_ad_id');
  static const String interstitialAdId =
      String.fromEnvironment('interstitial_ad_id');
  static const String appOpenAdId = String.fromEnvironment('app_open_ad_id');
  static const String rewardedAdId = String.fromEnvironment('rewarded_ad_id');
  static const String nativeAdId = String.fromEnvironment('native_ad_id');

  // --- Third-party services ---

  static const String oneSignalAppId =
      String.fromEnvironment('one_signal_app_id');
  static const String revenueCatApiKeyAndroid =
      String.fromEnvironment('revenue_cat_api_key_android');
  static const String posthogApiKey =
      String.fromEnvironment('posthog_api_key');
  static const String feedBackNestApiKey =
      String.fromEnvironment('feed_back_nest_api_key');

  /// Mixpanel project token. Empty -> the Mixpanel SDK is a silent no-op
  /// (see [mixpanelEnabled]); Firebase Analytics needs no token and stays on.
  static const String mixpanelToken = String.fromEnvironment('mixpanel_token');

  /// True only when a non-empty Mixpanel token was supplied via the env file.
  static bool get mixpanelEnabled => mixpanelToken.isNotEmpty;
  // --- Support / legal links (Settings "Support" section) ---

  static const String privacyPolicyUrl = String.fromEnvironment(
    'privacy_policy_url',
    defaultValue:
        'https://sites.google.com/view/simple-launcher-privacy-policy/home',
  );
  static const String termsUrl = String.fromEnvironment('terms_url');
  static const String appStoreUrl = String.fromEnvironment('app_store_url');
  static const String supportEmail = String.fromEnvironment(
    'support_email',
    defaultValue: 'support@genrevibes.com',
  );

  // --- Developer access (kit DeveloperAccessController) ---

  /// Blank keeps the kit's shared fallback passcode.
  static const String developerPasscode = String.fromEnvironment(
    'developer_passcode',
  );

  /// Comma-separated device *hashes* — never raw identifiers.
  static const String developerDeviceHashes = String.fromEnvironment(
    'developer_device_hashes',
  );

  /// Development-only simulation of an unlisted store build, so the hidden
  /// unlock gesture can be exercised on a dev device.
  static const bool developerAccessStoreBuild = bool.fromEnvironment(
    'developer_access_store_build',
    defaultValue: false,
  );

  /// Device hashes as the kit expects them: trimmed, blanks removed.
  static List<String> get developerDeviceHashList => developerDeviceHashes
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}
