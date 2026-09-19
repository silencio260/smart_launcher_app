import 'package:genrevibes_analytics/genrevibes_analytics.dart';
import 'package:genrevibes_core/genrevibes_core.dart';
import 'package:genrevibes_storage/genrevibes_storage.dart';

/// The user's answer to "may we collect analytics?", kept on the device.
///
/// The launcher shows no ads, so there is no ad-network consent form and no
/// IAB signal to store. What still needs an explicit answer is product
/// analytics and session replay: [AnalyticsConsent.unknown] means nobody has
/// been asked yet, and the pipeline stays silent until they are.
class AnalyticsConsentStore {
  /// Creates a store over the runtime's shared key-value store.
  const AnalyticsConsentStore(this._store);

  static const _key = 'launcher.analytics_consent.v1';

  final KeyValueStore _store;

  /// Reads the stored answer, treating an unreadable value as "not asked".
  Future<AnalyticsConsent> read() async {
    final result = await _store.getString(_key);
    final stored = result.fold(
      onSuccess: (value) => value,
      onFailure: (_) => null,
    );
    return switch (stored) {
      'granted' => AnalyticsConsent.granted,
      'denied' => AnalyticsConsent.denied,
      _ => AnalyticsConsent.unknown,
    };
  }

  /// Persists an answer. [AnalyticsConsent.unknown] clears it, which is what
  /// a developer reset does so the prompt can be seen again.
  Future<KitResult<void>> write(AnalyticsConsent consent) {
    if (consent == AnalyticsConsent.unknown) return _store.remove(_key);
    return _store.setString(_key, consent.name);
  }
}
