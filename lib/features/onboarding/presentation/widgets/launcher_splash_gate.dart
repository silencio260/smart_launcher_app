import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:genrevibes_splash/genrevibes_splash.dart';
import 'package:smart_launcher_app/core/ads/launcher_ads.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/core/utils/app_strings.dart';
import 'package:smart_launcher_app/core/widgets/launcher_brand_mark.dart';
import 'package:smart_launcher_app/features/onboarding/data/onboarding_store.dart';
import 'package:smart_launcher_app/features/onboarding/data/default_launcher_policy.dart';

/// Preparation only, never a fullscreen launch ad. Cold first-run onboarding
/// waits briefly for its native ad; configured default launchers skip this wait.
/// Warm icon launches preserve the navigator instead of resetting the home page.
class LauncherSplashGate extends StatefulWidget {
  const LauncherSplashGate({super.key, required this.child});
  final Widget child;

  @override
  State<LauncherSplashGate> createState() => _LauncherSplashGateState();
}

class _LauncherSplashGateState extends State<LauncherSplashGate> {
  static const _launches = MethodChannel(
    'com.genrevibes.smartlauncher/launches',
  );
  bool _released = false;
  bool _checking = true;
  bool _showSplash = false;
  int _generation = 0;
  Duration _splashBudget = const Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _launches.setMethodCallHandler((call) async {
      // Not arbitrary resumes: permission/consent/ad returns must not restart it.
      if (call.method == 'iconLaunch' && !_checking && !_showSplash) {
        await _checkLaunch();
      }
    });
    unawaited(_checkLaunch());
  }

  Future<void> _checkLaunch() async {
    final elapsed = Stopwatch()..start();
    _checking = true;
    LauncherAds.launchPreparing = true;
    final firstRun = !OnboardingStore.isCompletedSync;
    final isDefault = await LauncherService.isDefaultLauncher().timeout(
      const Duration(milliseconds: 800),
      // Uncertain role should never hold up someone's Home button.
      onTimeout: () => true,
    );
    if (!mounted) return;
    setState(() {
      _checking = false;
      _showSplash = firstRun || !isDefault;
      _generation++;
      _splashBudget = const Duration(seconds: 4) - elapsed.elapsed;
      if (_splashBudget.isNegative) _splashBudget = Duration.zero;
      if (!_showSplash) _released = true;
    });
    LauncherAds.launchPreparing = _showSplash;
    if (!_showSplash) unawaited(LauncherAds.prepareInlineAds());
  }

  @override
  void dispose() {
    _launches.setMethodCallHandler(null);
    LauncherAds.launchPreparing = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Do not mount onboarding before the cold preload attempt. On warm
        // launches retain its route state without painting ads under the splash.
        if (_released)
          Offstage(
            offstage: _showSplash,
            child: TickerMode(enabled: !_showSplash, child: widget.child),
          ),
        if (_checking && !_released)
          ColoredBox(color: theme.colorScheme.surface),
        if (_showSplash)
          SplashFlow(
            key: ValueKey(_generation),
            maxWait: _splashBudget,
            minDuration: Duration.zero,
            completionPause: Duration.zero,
            prepare: LauncherAds.prepareInlineAds,
            onFinished: (_) {
              if (!mounted) return;
              LauncherAds.launchPreparing = false;
              DefaultLauncherPolicy.requestReturnPrompt();
              debugPrint(
                'LauncherSplash: preparation window ended; opening app',
              );
              setState(() {
                _showSplash = false;
                _released = true;
              });
            },
            builder:
                (context, progress) => SplashLoadingView(
                  progress: progress,
                  title: AppStrings.appName,
                  logo: const LauncherBrandMark(),
                  labels: const SplashLabels(loading: 'Getting ready'),
                  style: SplashLoadingStyle(
                    backgroundColor: theme.colorScheme.surface,
                    progressColor: theme.colorScheme.primary,
                    progressTrackColor:
                        theme.colorScheme.surfaceContainerHighest,
                    titleStyle: theme.textTheme.headlineMedium,
                    progressLabelStyle: theme.textTheme.titleMedium,
                  ),
                ),
          ),
      ],
    );
  }
}
