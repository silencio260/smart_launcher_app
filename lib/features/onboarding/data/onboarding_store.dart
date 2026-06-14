import 'package:shared_preferences/shared_preferences.dart';

/// Launcher-feature ids that show a one-time first-open intro (Layer 2). Each
/// maps to a `LauncherFeatureCatalog` id and a bespoke onboarding screen.
const kMiniAppOnboardingIds = <String>[
  'app_locker',
  'app_hider',
  'file_locker',
  'alarm_clock',
];

/// Persists one-shot onboarding flags.
///
/// The completion flag is preloaded once in `main()` (via [preload]) so the
/// home gate in `MyApp` can read it synchronously and route to either the
/// onboarding flow or the launcher without a first-frame flash.
class OnboardingStore {
  OnboardingStore._();

  /// First-run launcher onboarding finished (completed OR explicitly skipped).
  static const _completedKey = 'onboarding_completed_v1';

  /// User dismissed the persistent "set as default" home-screen nudge.
  static const _nudgeDismissedKey = 'default_nudge_dismissed_v1';

  static bool? _completedCache;

  /// Ids of mini-apps whose first-open intro has been seen, cached for the
  /// synchronous gate inside each mini-app's `build`.
  static final Set<String> _miniAppOnboarded = {};

  static String _miniAppKey(String id) => 'miniapp_onboarded_${id}_v1';

  /// Warm the synchronous caches. Call once during startup before `runApp`.
  static Future<void> preload() async {
    final prefs = await SharedPreferences.getInstance();
    _completedCache = prefs.getBool(_completedKey) ?? false;
    _miniAppOnboarded.clear();
    for (final id in kMiniAppOnboardingIds) {
      if (prefs.getBool(_miniAppKey(id)) ?? false) _miniAppOnboarded.add(id);
    }
  }

  /// Synchronous read for the home gate. Falls back to `false` (show
  /// onboarding) until [preload] has run.
  static bool get isCompletedSync => _completedCache ?? false;

  static Future<void> markCompleted() async {
    _completedCache = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
  }

  static Future<bool> isNudgeDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_nudgeDismissedKey) ?? false;
  }

  static Future<void> dismissNudge() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_nudgeDismissedKey, true);
  }

  // --- Mini-app first-open intros (Layer 2) ---

  /// Synchronous gate read for a mini-app's `build`. False until [preload] runs.
  static bool isMiniAppOnboardedSync(String id) =>
      _miniAppOnboarded.contains(id);

  /// Marks a mini-app's intro as seen. Updates the sync cache immediately so a
  /// `setState` right after this hides the intro without awaiting the write.
  static Future<void> markMiniAppOnboarded(String id) async {
    _miniAppOnboarded.add(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_miniAppKey(id), true);
  }

  static Future<bool> isMiniAppOnboarded(String id) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_miniAppKey(id)) ?? false;
  }

  /// Clears a mini-app's intro flag so it shows again next open (Dev View).
  static Future<void> resetMiniAppOnboarded(String id) async {
    _miniAppOnboarded.remove(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_miniAppKey(id));
  }

  // --- Dev / debug helpers (Settings > Dev View > Onboarding) ---

  /// Async read of completion for the debug screen (mirrors the sync cache).
  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_completedKey) ?? false;
  }

  /// Clears the completion flag so the launcher onboarding shows again on the
  /// next cold start (and the sync gate routes to it).
  static Future<void> resetCompleted() async {
    _completedCache = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_completedKey);
  }

  /// Clears the dismissed flag so the "set as default" home nudge reappears.
  static Future<void> resetNudge() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nudgeDismissedKey);
  }
}
