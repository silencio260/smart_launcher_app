import 'dart:async';

import 'package:flutter/material.dart';

import 'package:smart_launcher_app/core/analytics/app_events.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/features/home/presentation/screens/home_screen.dart';
import 'package:smart_launcher_app/features/onboarding/data/default_launcher_policy.dart';
import 'package:smart_launcher_app/features/onboarding/data/onboarding_store.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/widgets/set_default_page.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/widgets/wallpaper_page.dart';

/// Set-as-default step that follows onboarding. Granting the role moves on to
/// [WallpaperSetupScreen] at once. Coming back without it shows an error under
/// the button and, unless the role is forced remotely, a close button that
/// also moves on.
class SetDefaultScreen extends StatefulWidget {
  const SetDefaultScreen({super.key, this.previewMode = false});

  /// Dev View preview: returns to the debug screen at the end and persists
  /// nothing.
  final bool previewMode;

  @override
  State<SetDefaultScreen> createState() => _SetDefaultScreenState();
}

class _SetDefaultScreenState extends State<SetDefaultScreen>
    with WidgetsBindingObserver {
  StreamSubscription<Object?>? _policy;
  bool _asked = false;
  bool _requestInFlight = false;
  bool _returnedWithoutRole = false;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppAnalytics.onboardingPageViewed('set_default');
    _policy = DefaultLauncherPolicy.changes.listen((_) {
      if (mounted) setState(() {});
    });
    // Already the default (e.g. set from system settings): move straight on.
    if (!widget.previewMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkRole());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _policy?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The grant happens in Android's own dialog or settings; re-check on the
    // way back, once more a moment later in case the change lands late.
    if (state != AppLifecycleState.resumed || !_asked) return;
    unawaited(() async {
      if (await _checkRole()) return;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted || await _checkRole()) return;
      if (mounted) setState(() => _returnedWithoutRole = true);
    }());
  }

  /// Moves on as soon as this app holds the home role.
  Future<bool> _checkRole() async {
    final isDefault = await LauncherService.isDefaultLauncher();
    if (!mounted || !isDefault || _left) return isDefault;
    AppAnalytics.launcherSetDefault(true);
    _goToWallpaper(declinedDefault: false);
    return true;
  }

  Future<void> _requestRole() async {
    if (_requestInFlight) return;
    _asked = true;
    setState(() {
      _requestInFlight = true;
      _returnedWithoutRole = false;
    });
    AppAnalytics.onboardingDefaultRequested();
    final launched = await LauncherService.requestHomeRole();
    if (!mounted) return;
    setState(() {
      _requestInFlight = false;
      if (!launched) _returnedWithoutRole = true;
    });
  }

  void _goToWallpaper({required bool declinedDefault}) {
    if (_left || !mounted) return;
    _left = true;
    if (declinedDefault) AppAnalytics.onboardingSkipped();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => WallpaperSetupScreen(previewMode: widget.previewMode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canClose = _returnedWithoutRole && !DefaultLauncherPolicy.forced;
    return PopScope(
      canPop: widget.previewMode,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: SetDefaultPage(
            requestInFlight: _requestInFlight,
            onSetDefault: _requestRole,
            showNotDefaultError: _returnedWithoutRole && !_requestInFlight,
            onClose: canClose
                ? () => _goToWallpaper(declinedDefault: true)
                : null,
          ),
        ),
      ),
    );
  }
}

/// Wallpaper step after set-as-default; setting a wallpaper or closing it
/// opens the launcher.
class WallpaperSetupScreen extends StatefulWidget {
  const WallpaperSetupScreen({super.key, this.previewMode = false});

  final bool previewMode;

  @override
  State<WallpaperSetupScreen> createState() => _WallpaperSetupScreenState();
}

class _WallpaperSetupScreenState extends State<WallpaperSetupScreen> {
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    AppAnalytics.onboardingPageViewed('wallpaper');
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    if (widget.previewMode) {
      // The wallpaper preview may still be on top; remove this screen itself.
      final route = ModalRoute.of(context);
      if (route != null) Navigator.of(context).removeRoute(route);
      return;
    }
    final isDefault = await LauncherService.isDefaultLauncher();
    AppAnalytics.onboardingCompleted(setDefault: isDefault);
    await OnboardingStore.markSetupCompleted();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen(firstRun: true)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.previewMode,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(child: WallpaperPage(onDone: _finish)),
      ),
    );
  }
}
