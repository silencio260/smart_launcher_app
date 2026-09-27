import 'package:genrevibes_onboarding/genrevibes_onboarding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_launcher_app/bootstrap/app_runtime.dart';
import 'package:smart_launcher_app/container_injector.dart';

/// Launcher-feature ids that show a one-time first-open intro (Layer 2). Each
/// maps to a `LauncherFeatureCatalog` id and a bespoke onboarding screen.
const kMiniAppOnboardingIds = <String>[
  'app_locker',
  'app_hider',
  'file_locker',
  'alarm_clock',
];

/// Persists the launcher's one-shot flags around onboarding.
///
/// Completion of the three onboarding screens belongs to the kit's
/// `OnboardingController` (`AppRuntime.onboarding`); this reads it for the
/// synchronous home gate. The set-as-default + wallpaper setup flag and the
/// mini-app intro flags are app-owned and preloaded in `main()` ([preload]).
class OnboardingStore {
  OnboardingStore._();

  /// Where the launcher recorded onboarding completion before the kit
  /// controller. The runtime's migrating store adopts it.
  static const legacyCompletedKey = 'onboarding_completed_v1';

  /// The set-as-default and wallpaper steps that follow onboarding finished.
  static const _setupCompletedKey = 'setup_completed_v1';

  /// User dismissed the persistent "set as default" home-screen nudge.
  static const _nudgeDismissedKey = 'default_nudge_dismissed_v1';

  static bool? _setupCompletedCache;

  /// Ids of mini-apps whose first-open intro has been seen, cached for the
  /// synchronous gate inside each mini-app's `build`.
  static final Set<String> _miniAppOnboarded = {};

  static String _miniAppKey(String id) => 'miniapp_onboarded_${id}_v1';

  /// Warm the synchronous caches. Call once during startup before `runApp`.
  static Future<void> preload() async {
    final prefs = await SharedPreferences.getInstance();
    // Installs from before these steps existed finished onboarding without
    // them, so a missing flag follows onboarding completion.
    _setupCompletedCache = prefs.getBool(_setupCompletedKey) ??
        prefs.getBool(OnboardingKeys.completed) ??
        prefs.getBool(legacyCompletedKey) ??
        false;
    _miniAppOnboarded.clear();
    for (final id in kMiniAppOnboardingIds) {
      if (prefs.getBool(_miniAppKey(id)) ?? false) _miniAppOnboarded.add(id);
    }
  }

  static OnboardingController? get _controller =>
      sl.isRegistered<AppRuntime>() ? sl<AppRuntime>().onboarding : null;

  /// Synchronous read for the home gate. False (show onboarding) until the
  /// runtime's controller has initialized.
  static bool get isCompletedSync => _controller?.isCompleted ?? false;

  /// Records that setup still has to run, right as onboarding completes, so
  /// a restart mid-setup resumes it instead of following [preload]'s
  /// fallback for older installs.
  static Future<void> markSetupPending() async {
    _setupCompletedCache ??= false;
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_setupCompletedKey)) {
      await prefs.setBool(_setupCompletedKey, false);
    }
  }

  /// Synchronous read for the home gate. False until [preload] has run.
  static bool get isSetupCompletedSync => _setupCompletedCache ?? false;

  static Future<void> markSetupCompleted() async {
    _setupCompletedCache = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupCompletedKey, true);
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

  /// Completion for the debug screen.
  static Future<bool> isCompleted() async => isCompletedSync;

  /// Clears completion and setup so the launcher onboarding shows again on
  /// the next cold start (and the sync gate routes to it).
  static Future<void> resetCompleted() async {
    await _controller?.reset();
    _setupCompletedCache = false;
    final prefs = await SharedPreferences.getInstance();
    // The migrating store would otherwise adopt the old flag again.
    await prefs.remove(legacyCompletedKey);
    await prefs.remove(_setupCompletedKey);
  }

  /// Clears the dismissed flag so the "set as default" home nudge reappears.
  static Future<void> resetNudge() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nudgeDismissedKey);
  }
}
