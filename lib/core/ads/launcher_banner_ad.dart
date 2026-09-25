import 'dart:async';
import 'package:flutter/material.dart';
import 'package:genrevibes_ads/genrevibes_ads.dart';
import 'package:genrevibes_core/genrevibes_core.dart';
import 'package:genrevibes_ads_yodo1/genrevibes_ads_yodo1.dart';
import 'package:smart_launcher_app/bootstrap/app_runtime.dart';
import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/analytics/app_events.dart';
import 'package:smart_launcher_app/core/ads/launcher_ad_load_boundary.dart';

/// A banner for the bottom of a mini-app screen.
///
/// Renders nothing at all — no reserved space, no placeholder — when ads are
/// unconfigured, the provider is not ready, or the remote policy has ads off,
/// so a build without an ad key looks exactly as it did before.
///
/// Never place this on the home screen or in the app drawer.
class LauncherBannerAd extends StatefulWidget {
  /// Creates a banner slot.
  const LauncherBannerAd({
    super.key,
    required this.placement,
    this.size = Yodo1BannerSize.standard,
  });

  /// Placement this banner is reported under.
  final AdPlacement placement;

  /// Banner shape to request.
  final Yodo1BannerSize size;

  @override
  State<LauncherBannerAd> createState() => _LauncherBannerAdState();
}

class _LauncherBannerAdState extends State<LauncherBannerAd>
    with WidgetsBindingObserver {
  bool _recordedImpression = false;
  bool _foreground = true;
  Timer? _policyWakeup;
  String? _lastSkipReason;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _foreground = state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    _policyWakeup?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  AdPlacement get placement => widget.placement;
  Yodo1BannerSize get size => widget.size;

  Widget _skip(AppRuntime? runtime, String reason) {
    if (_lastSkipReason != reason) {
      runtime?.logger.log(
        KitLogLevel.info,
        'Banner slot skipped.',
        moduleId: 'ads.banner',
        fields: <String, Object?>{'placement': placement.id, 'reason': reason},
      );
    }
    _lastSkipReason = reason;
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = sl.isRegistered<AppRuntime>() ? sl<AppRuntime>() : null;
    if (runtime == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: runtime,
      builder:
          (context, _) => StreamBuilder<Object>(
            stream: runtime.adPolicyBinder?.healthChanges,
            builder:
                (context, _) => StreamBuilder<Object>(
                  stream: runtime.adProvider?.healthChanges,
                  builder: (context, _) => _buildSlot(runtime),
                ),
          ),
    );
  }

  Widget _buildSlot(AppRuntime runtime) {
    final provider = runtime.adProvider;
    final policy = runtime.adPolicy;
    // Skipping is normal — no ad key, provider still starting, policy off —
    // but a silent skip is indistinguishable from a broken banner, so say
    // which it was.
    if (provider == null || policy == null) {
      return _skip(runtime, 'ads are not configured in this build');
    }
    if (!provider.health.isOperational) {
      return _skip(runtime, 'provider is ${provider.health.state.name}');
    }
    final decision = policy.evaluate(placement);
    if (!decision.isAllowed &&
        !(_recordedImpression &&
            decision.blockReason == AdPolicyBlockReason.frequencyCap)) {
      _recordedImpression = false;
      if (_foreground &&
          (decision.blockReason == AdPolicyBlockReason.frequencyCap ||
              decision.blockReason == AdPolicyBlockReason.initialDelay) &&
          !(_policyWakeup?.isActive ?? false)) {
        _policyWakeup = Timer(const Duration(seconds: 1), () {
          if (mounted && _foreground) setState(() {});
        });
      }
      return _skip(runtime, 'policy blocked: ${decision.blockReason?.name}');
    }
    _lastSkipReason = null;
    _policyWakeup?.cancel();

    return Offstage(
      offstage: !_foreground,
      child: LauncherAdLoadBoundary(
        key: ValueKey(placement.id),
        placement: placement,
        active: _foreground,
        canRetry:
            () =>
                _foreground &&
                provider.health.isOperational &&
                policy.evaluate(placement).isAllowed,
        builder:
            (attempt, onEvent, onFailure) => SafeArea(
              top: false,
              child: Yodo1BannerView(
                key: ValueKey(attempt),
                placement: placement,
                size: size,
                onLoadFailed: onFailure,
                onEvent: (event) {
                  if (!onEvent(event)) return;
                  if (event.type == AdEventType.paid && !_recordedImpression) {
                    _recordedImpression = true;
                    policy.recordShown(placement);
                  }
                  AppAnalytics.adLifecycle(
                    adType: 'banner',
                    action: event.type.name,
                    result: 'success',
                    source: placement.id,
                    testAds: false,
                  );
                },
              ),
            ),
      ),
    );
  }
}
