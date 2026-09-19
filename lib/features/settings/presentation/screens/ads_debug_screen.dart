import 'dart:async';

import 'package:flutter/material.dart';
import 'package:genrevibes_ads/genrevibes_ads.dart';
import 'package:genrevibes_ads_admob/genrevibes_ads_admob.dart';
import 'package:genrevibes_ads_admob_ui/genrevibes_ads_admob_ui.dart';
import 'package:genrevibes_core/genrevibes_core.dart';
import 'package:smart_launcher_app/bootstrap/app_runtime.dart';
import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/ads/test_ads_config.dart';
import 'package:smart_launcher_app/core/analytics/app_events.dart';
import 'package:smart_launcher_app/core/config/app_env.dart';

typedef AdLifecycleLogger =
    void Function({
      required String adType,
      required String action,
      required String result,
      String source,
      bool testAds,
      String? error,
    });

class AdsDebugScreen extends StatefulWidget {
  const AdsDebugScreen({
    super.key,
    this.configOverride,
    this.adsProviderOverride,
    this.showAdPreviews = true,
    this.lifecycleLogger = AppAnalytics.adLifecycle,
  });

  final GenRevibesAdMobConfiguration? configOverride;
  final AdProvider? adsProviderOverride;
  final bool showAdPreviews;
  final AdLifecycleLogger lifecycleLogger;

  @override
  State<AdsDebugScreen> createState() => _AdsDebugScreenState();
}

class _AdsDebugScreenState extends State<AdsDebugScreen> {
  late final GenRevibesAdMobConfiguration? _config =
      widget.configOverride ?? TestAdsConfig.fromAppEnv();
  late final AdProvider? _provider =
      widget.adsProviderOverride ??
      (sl.isRegistered<AppRuntime>() ? sl<AppRuntime>().ads : null);
  StreamSubscription<ModuleHealth>? _health;
  StreamSubscription<AdEvent>? _events;
  final Set<String> _busy = {};
  late final _nativeRequests = <String, AdMobNativeRequest>{
    for (final unit in _config?.adUnits.values ?? const <AdMobAdUnit>[])
      if (unit.placement.format == AdFormat.native)
        unit.placement.id: AdMobNativeRequest(unit: unit),
  };
  String _status = 'Ready for a request';

  @override
  void initState() {
    super.initState();
    _health = _provider?.healthChanges.listen((_) {
      if (mounted) setState(() {});
    });
    _events = _provider?.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _health?.cancel();
    _events?.cancel();
    super.dispose();
  }

  void _log(String type, String action, String result, {String? error}) =>
      widget.lifecycleLogger(
        adType: type,
        action: action,
        result: result,
        source: 'dev_panel',
        testAds: true,
        error: error,
      );

  String _type(AdFormat format) =>
      format == AdFormat.appOpen ? 'app_open' : format.name;

  void _onEvent(AdEvent event) {
    _log(_type(event.format), event.type.name, 'success');
    if (mounted) setState(() {});
  }

  Future<void> _run(
    String id,
    String type,
    String action,
    Future<KitResult<Object?>> Function() operation,
  ) async {
    setState(() => _busy.add(id));
    _log(type, action, 'requested');
    try {
      final result = await operation();
      result.fold(
        onSuccess: (value) {
          final outcome =
              value is AdShowResult && !value.wasShown
                  ? value.status.name
                  : 'success';
          _status = '$type $action: $outcome';
          _log(type, action, outcome);
        },
        onFailure: (error) {
          _status = error.message;
          _log(type, action, 'failure', error: error.message);
        },
      );
    } catch (error) {
      _status = error.toString();
      _log(type, action, 'failure', error: error.toString());
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    final config = _config;
    final ready = provider?.health.isOperational ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Ads')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            title: const Text('Development mode'),
            subtitle: Text(
              AppEnv.developmentMode ? 'enabled — sample ads' : 'disabled',
            ),
          ),
          ListTile(
            title: const Text('AdMob provider'),
            subtitle: Text(provider?.health.state.name ?? 'not configured'),
          ),
          ListTile(
            title: const Text('Last operation'),
            subtitle: Text(_status),
          ),
          if (provider == null || config == null)
            const ListTile(
              title: Text('Test ads disabled'),
              subtitle: Text('Run with env/dev.json or env/special_dev.json.'),
            )
          else ...[
            ListTile(
              title: const Text('Initialize test ads'),
              trailing: const Icon(Icons.power_settings_new),
              onTap:
                  _busy.isNotEmpty
                      ? null
                      : () => _run(
                        'initialize',
                        'all',
                        'initialize',
                        () async => (await provider.initialize()).map<Object?>(
                          (_) => null,
                        ),
                      ),
            ),
            for (final unit in config.adUnits.values) ...[
              const Divider(),
              ListTile(
                title: Text(_type(unit.placement.format)),
                subtitle: Text(unit.adUnitId),
              ),
              if (provider.supportedFormats.contains(unit.placement.format))
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FilledButton.tonal(
                      onPressed:
                          !ready || _busy.contains(unit.placement.id)
                              ? null
                              : () => _run(
                                unit.placement.id,
                                _type(unit.placement.format),
                                'load',
                                () async => (await provider.load(
                                  unit.placement,
                                )).map<Object?>((_) => null),
                              ),
                      child: const Text('Load'),
                    ),
                    FilledButton(
                      onPressed:
                          !ready ||
                                  _busy.contains(unit.placement.id) ||
                                  !provider.isReady(unit.placement)
                              ? null
                              : () => _run(
                                unit.placement.id,
                                _type(unit.placement.format),
                                'show',
                                () async => (await provider.show(
                                  unit.placement,
                                )).map<Object?>((value) => value),
                              ),
                      child: const Text('Show'),
                    ),
                  ],
                ),
              if (widget.showAdPreviews &&
                  ready &&
                  unit.placement.format == AdFormat.banner)
                Center(
                  child: AdMobBannerView(
                    request: AdMobBannerRequest(unit: unit),
                    enabled: true,
                    onEvent: _onEvent,
                    placeholderBuilder: _placeholder,
                  ),
                ),
              if (widget.showAdPreviews &&
                  ready &&
                  unit.placement.format == AdFormat.native)
                Center(
                  child: AdMobNativeView(
                    request: _nativeRequests[unit.placement.id]!,
                    enabled: true,
                    onEvent: _onEvent,
                    placeholderBuilder: _placeholder,
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context, Object? error) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(error == null ? 'Loading ad…' : 'Ad failed: $error'),
  );
}
