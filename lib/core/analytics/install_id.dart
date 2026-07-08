import 'package:smart_launcher_app/core/storage/feature_hive_store.dart';
import 'package:uuid/uuid.dart';

/// Anonymous, stable per-install identifier.
///
/// Used as the analytics user id (Firebase + Crashlytics + Mixpanel) and the
/// session-replay distinct id. It is a random UUID — NOT tied to any account,
/// device id, or PII — so crashes/sessions group per install while staying
/// privacy-safe.
class InstallId {
  InstallId._();

  static const _key = 'analytics_install_uuid_v1';
  static String? _cached;

  /// Returns the existing install UUID, minting and persisting one on first run.
  /// Requires [FeatureHiveStore.init] to have run (boxes open).
  static String getOrCreate() {
    final existing = _cached;
    if (existing != null) return existing;

    final box = FeatureHiveStore.box(FeatureHiveBoxes.featureSettings);
    final stored = box.get(_key) as String?;
    if (stored != null && stored.isNotEmpty) {
      _cached = stored;
      return stored;
    }

    final fresh = const Uuid().v4();
    box.put(_key, fresh);
    _cached = fresh;
    return fresh;
  }
}
