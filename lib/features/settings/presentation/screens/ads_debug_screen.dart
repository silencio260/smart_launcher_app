import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:genrevibes_starter_kit/starter_kit.dart';

import 'package:smart_launcher_app/core/ads/test_ads_config.dart';
import 'package:smart_launcher_app/core/analytics/app_events.dart';
import 'package:smart_launcher_app/core/config/app_env.dart';

typedef AdLifecycleLogger = void Function({
  required String adType,
  required String action,
  required String result,
  String source,
  bool testAds,
  String? error,
});

class AdsDebugScreen extends StatefulWidget {
  final AdsConfig? configOverride;
  final AdsBloc? adsBlocOverride;
  final bool showAdPreviews;
  final AdLifecycleLogger lifecycleLogger;

  const AdsDebugScreen({
    super.key,
    this.configOverride,
    this.adsBlocOverride,
    this.showAdPreviews = true,
    this.lifecycleLogger = AppAnalytics.adLifecycle,
  });

  @override
  State<AdsDebugScreen> createState() => _AdsDebugScreenState();
}

class _AdsDebugScreenState extends State<AdsDebugScreen> {
  final Map<AdType, String> _pendingActions = {};

  AdsConfig? get _config => widget.configOverride ?? TestAdsConfig.fromAppEnv();

  AdsBloc? get _adsBloc {
    final override = widget.adsBlocOverride;
    if (override != null) return override;
    if (!StarterKit.sl.isRegistered<AdsBloc>()) return null;
    return StarterKit.adsBloc;
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final bloc = _adsBloc;
    final adsEnabled = config != null && bloc != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Ads')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _SectionHeader('Environment'),
          _StatusTile(
            label: 'Development mode',
            value: AppEnv.developmentMode ? 'enabled' : 'disabled',
            active: AppEnv.developmentMode,
          ),
          _StatusTile(
            label: 'Ads bloc',
            value: bloc == null ? 'not registered' : 'registered',
            active: bloc != null,
          ),
          if (config == null)
            const ListTile(
              leading: Icon(Icons.block_outlined),
              title: Text('Test ads disabled'),
              subtitle: Text('Run with env/dev.json or env/special_dev.json.'),
            )
          else ...[
            _AdUnitTile(label: 'Banner', value: config.bannerAdUnitId),
            _AdUnitTile(
                label: 'Interstitial', value: config.interstitialAdUnitId),
            _AdUnitTile(label: 'App open', value: config.appOpenAdUnitId),
            _AdUnitTile(label: 'Rewarded', value: config.rewardedAdUnitId),
            _AdUnitTile(label: 'Native', value: config.nativeAdUnitId),
          ],
          const Divider(),
          const _SectionHeader('Controls'),
          if (bloc == null)
            const ListTile(
              leading: Icon(Icons.warning_amber_outlined),
              title: Text('StarterKit ads are not initialized'),
            )
          else
            BlocConsumer<AdsBloc, AdsState>(
              bloc: bloc,
              listener: _handleAdsState,
              builder: (context, state) {
                return Column(
                  children: [
                    _AdsStateTile(state: state),
                    _ActionTile(
                      icon: Icons.power_settings_new,
                      title: 'Initialize test ads',
                      enabled: adsEnabled,
                      onTap: () {
                        if (config == null) return;
                        _logLifecycle(
                          adType: 'all',
                          action: 'initialize',
                          result: 'requested',
                        );
                        bloc.add(AdsInitialize(config: config));
                      },
                    ),
                    _ActionTile(
                      icon: Icons.download_outlined,
                      title: 'Load interstitial',
                      enabled: _hasUnit(config?.interstitialAdUnitId),
                      onTap: () => _dispatch(
                        bloc,
                        AdType.interstitial,
                        'load',
                        AdsLoadInterstitial(
                          adUnitId: config!.interstitialAdUnitId!,
                        ),
                      ),
                    ),
                    _ActionTile(
                      icon: Icons.open_in_full_outlined,
                      title: 'Show interstitial',
                      enabled: state is AdsReady && state.isInterstitialReady,
                      onTap: () => _dispatch(
                        bloc,
                        AdType.interstitial,
                        'show',
                        const AdsShowInterstitial(),
                      ),
                    ),
                    _ActionTile(
                      icon: Icons.download_for_offline_outlined,
                      title: 'Load rewarded',
                      enabled: _hasUnit(config?.rewardedAdUnitId),
                      onTap: () => _dispatch(
                        bloc,
                        AdType.rewarded,
                        'load',
                        AdsLoadRewarded(adUnitId: config!.rewardedAdUnitId!),
                      ),
                    ),
                    _ActionTile(
                      icon: Icons.workspace_premium_outlined,
                      title: 'Show rewarded',
                      enabled: state is AdsReady && state.isRewardedReady,
                      onTap: () => _dispatch(
                        bloc,
                        AdType.rewarded,
                        'show',
                        const AdsShowRewarded(),
                      ),
                    ),
                    _ActionTile(
                      icon: Icons.file_download_outlined,
                      title: 'Load app-open',
                      enabled: _hasUnit(config?.appOpenAdUnitId),
                      onTap: () => _dispatch(
                        bloc,
                        AdType.appOpen,
                        'load',
                        AdsLoadAppOpen(adUnitId: config!.appOpenAdUnitId!),
                      ),
                    ),
                    _ActionTile(
                      icon: Icons.app_shortcut_outlined,
                      title: 'Show app-open',
                      enabled: state is AdsReady && state.isAppOpenReady,
                      onTap: () => _dispatch(
                        bloc,
                        AdType.appOpen,
                        'show',
                        const AdsShowAppOpen(),
                      ),
                    ),
                  ],
                );
              },
            ),
          if (adsEnabled && widget.showAdPreviews) ...[
            const Divider(),
            const _SectionHeader('Inline previews'),
            _defaultAdPreviews(config),
          ],
        ],
      ),
    );
  }

  void _dispatch(AdsBloc bloc, AdType type, String action, AdsEvent event) {
    _pendingActions[type] = action;
    _logLifecycle(
      adType: _typeName(type),
      action: action,
      result: 'requested',
    );
    bloc.add(event);
  }

  void _handleAdsState(BuildContext context, AdsState state) {
    if (state is AdsReady) {
      _completeReady(AdType.interstitial, state.isInterstitialReady);
      _completeReady(AdType.rewarded, state.isRewardedReady);
      _completeReady(AdType.appOpen, state.isAppOpenReady);
      _completeReady(AdType.native, state.isNativeReady);
    } else if (state is AdsShowSuccess) {
      final action = _pendingActions.remove(state.type) ?? 'show';
      _logLifecycle(
        adType: _typeName(state.type),
        action: action,
        result: 'success',
      );
    } else if (state is AdsError) {
      if (_pendingActions.isEmpty) {
        _logLifecycle(
          adType: 'unknown',
          action: 'unknown',
          result: 'failure',
          error: state.message,
        );
        return;
      }
      final failures = Map<AdType, String>.from(_pendingActions);
      _pendingActions.clear();
      failures.forEach((type, action) {
        _logLifecycle(
          adType: _typeName(type),
          action: action,
          result: 'failure',
          error: state.message,
        );
      });
    } else if (state is AdsInitialized) {
      _logLifecycle(
        adType: 'all',
        action: 'initialize',
        result: 'success',
      );
    }
  }

  void _completeReady(AdType type, bool ready) {
    if (!ready) return;
    final action = _pendingActions[type];
    if (action != 'load') return;
    const completedAction = 'load';
    _pendingActions.remove(type);
    _logLifecycle(
      adType: _typeName(type),
      action: completedAction,
      result: 'success',
    );
  }

  void _logLifecycle({
    required String adType,
    required String action,
    required String result,
    String? error,
  }) {
    widget.lifecycleLogger(
      adType: adType,
      action: action,
      result: result,
      source: 'dev_panel',
      testAds: true,
      error: error,
    );
  }

  static bool _hasUnit(String? value) => value != null && value.isNotEmpty;

  static String _typeName(AdType type) => switch (type) {
        AdType.banner => 'banner',
        AdType.interstitial => 'interstitial',
        AdType.rewarded => 'rewarded',
        AdType.native => 'native',
        AdType.appOpen => 'app_open',
      };

  static Widget _defaultAdPreviews(AdsConfig config) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_hasUnit(config.bannerAdUnitId))
          StarterKit.bannerAd(adUnitId: config.bannerAdUnitId),
        if (_hasUnit(config.nativeAdUnitId))
          StarterKit.nativeAd(adUnitId: config.nativeAdUnitId),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final String label;
  final String value;
  final bool active;

  const _StatusTile({
    required this.label,
    required this.value,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        active ? Icons.check_circle_outline : Icons.cancel_outlined,
        color: active ? Colors.green : Theme.of(context).disabledColor,
      ),
      title: Text(label),
      trailing: Text(value),
    );
  }
}

class _AdUnitTile extends StatelessWidget {
  final String label;
  final String? value;

  const _AdUnitTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final resolved = value;
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: Text(_redact(resolved)),
    );
  }

  static String _redact(String? value) {
    if (value == null || value.isEmpty) return 'not configured';
    final split = value.split('/');
    if (split.length != 2) return 'configured';
    final suffix = split.last;
    final visible =
        suffix.length <= 4 ? suffix : suffix.substring(suffix.length - 4);
    return '${split.first}/...$visible';
  }
}

class _AdsStateTile extends StatelessWidget {
  final AdsState state;

  const _AdsStateTile({required this.state});

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (state) {
      AdsReady s =>
        'interstitial=${s.isInterstitialReady}, rewarded=${s.isRewardedReady}, appOpen=${s.isAppOpenReady}, native=${s.isNativeReady}',
      AdsError s => s.message,
      _ => state.runtimeType.toString(),
    };
    return ListTile(
      leading: const Icon(Icons.monitor_heart_outlined),
      title: const Text('Ads state'),
      subtitle: Text(subtitle),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: enabled ? onTap : null,
    );
  }
}
