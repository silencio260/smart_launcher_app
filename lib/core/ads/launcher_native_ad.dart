import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:smart_launcher_app/core/ads/launcher_ad_load_boundary.dart';
import 'package:smart_launcher_app/core/ads/launcher_ads.dart';
import 'package:flutter/material.dart';
import 'package:genrevibes_ads/genrevibes_ads.dart';
import 'package:genrevibes_ads_yodo1/genrevibes_ads_yodo1.dart';
import 'package:smart_launcher_app/bootstrap/app_runtime.dart';
import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/analytics/app_events.dart';

/// An in-layout MAS native ad. The Android view owns and destroys its creative.
/// Collapses until detached inventory is ready, then fits the creative exactly.
class LauncherNativeAd extends StatefulWidget {
  const LauncherNativeAd({
    super.key,
    required this.placement,
    this.enabled = true,
  });

  final AdPlacement placement;
  final bool enabled;

  @override
  State<LauncherNativeAd> createState() => _LauncherNativeAdState();
}

class _LauncherNativeAdState extends State<LauncherNativeAd>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  bool _foreground = true;
  bool _recordedImpression = false;
  bool _started = false;
  Timer? _policyWakeup;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didUpdateWidget(LauncherNativeAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.placement != widget.placement) {
      if (_started) LauncherAds.inlineUnmounted(oldWidget.placement);
      _recordedImpression = false;
      _started = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
    });
  }

  @override
  void dispose() {
    if (_started) LauncherAds.inlineUnmounted(widget.placement);
    _policyWakeup?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (defaultTargetPlatform != TargetPlatform.android ||
        !sl.isRegistered<AppRuntime>()) {
      return const SizedBox.shrink();
    }
    final runtime = sl<AppRuntime>();
    return LayoutBuilder(
      builder: (context, constraints) {
        // Do not crop a compact creative in split-screen or a narrow parent.
        if (constraints.maxWidth < LauncherAds.nativeWidth) {
          return const SizedBox.shrink();
        }
        return AnimatedBuilder(
          animation: runtime,
          builder: (context, _) => StreamBuilder<Object>(
            stream: runtime.adPolicyBinder?.healthChanges,
            builder: (context, _) => StreamBuilder<Object>(
              stream: runtime.adProvider?.healthChanges,
              builder: (context, _) {
                final provider = runtime.adProvider;
                final policy = runtime.adPolicy;
                if (provider == null || policy == null) {
                  return const SizedBox.shrink();
                }
                if (widget.placement == LauncherAdPlacements.onboardingNative &&
                    !LauncherAds.onboardingAdAllowed) {
                  return const SizedBox.shrink();
                }
                final decision = policy.evaluate(widget.placement);
                // A cap prevents the next creative, not the one already displayed.
                final allowed =
                    decision.isAllowed ||
                    (_recordedImpression &&
                        decision.blockReason ==
                            AdPolicyBlockReason.frequencyCap);
                if (!allowed) {
                  _recordedImpression = false;
                  if (_foreground &&
                      widget.enabled &&
                      (decision.blockReason ==
                              AdPolicyBlockReason.frequencyCap ||
                          decision.blockReason ==
                              AdPolicyBlockReason.initialDelay) &&
                      !(_policyWakeup?.isActive ?? false)) {
                    _policyWakeup = Timer(const Duration(seconds: 1), () {
                      if (mounted && _foreground && widget.enabled) {
                        setState(() {});
                      }
                    });
                  }
                  return const SizedBox.shrink();
                }
                _policyWakeup?.cancel();
                if (!provider.health.isOperational) {
                  return const SizedBox.shrink();
                }
                if (!_started && (!widget.enabled || !_foreground)) {
                  return const SizedBox.shrink();
                }
                if (!_started) LauncherAds.inlineMounted(widget.placement);
                _started = true;
                return Offstage(
                  offstage: !widget.enabled || !_foreground,
                  child: LauncherAdLoadBoundary(
                    key: ValueKey(widget.placement.id),
                    placement: widget.placement,
                    active: widget.enabled && _foreground,
                    canRetry: () =>
                        widget.enabled &&
                        _foreground &&
                        provider.health.isOperational &&
                        policy.evaluate(widget.placement).isAllowed,
                    prepare: () => Yodo1InlinePreloads.load(
                      widget.placement,
                      backgroundColor: LauncherAds.nativeBackgroundColor,
                      widthPx:
                          (LauncherAds.nativeWidth *
                                  View.of(context).devicePixelRatio)
                              .round(),
                      heightPx:
                          (LauncherAds.nativeHeight *
                                  View.of(context).devicePixelRatio)
                              .round(),
                    ),
                    builder: (attempt, onEvent, onFailure) => Center(
                      heightFactor: 1,
                      child: SizedBox(
                        width: LauncherAds.nativeWidth,
                        height: LauncherAds.nativeHeight,
                        child: Yodo1NativeView(
                          key: ValueKey(attempt),
                          placement: widget.placement,
                          height: LauncherAds.nativeHeight,
                          backgroundColor: LauncherAds.nativeBackgroundColor,
                          onLoadFailed: onFailure,
                          onEvent: (event) {
                            if (!onEvent(event)) return;
                            // MAS's paid callback accompanies an impression. Loading
                            // alone is not evidence that an off-screen ad was seen.
                            if (event.type == AdEventType.paid &&
                                !_recordedImpression) {
                              _recordedImpression = true;
                              policy.recordShown(widget.placement);
                            }
                            AppAnalytics.adLifecycle(
                              adType: 'native',
                              action: event.type.name,
                              result: 'success',
                              source: widget.placement.id,
                              testAds: false,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
