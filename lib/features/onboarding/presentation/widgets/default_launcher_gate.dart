import 'dart:async';

import 'package:flutter/material.dart';

import 'package:smart_launcher_app/core/analytics/app_events.dart';
import 'package:smart_launcher_app/core/ads/launcher_ads.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/features/onboarding/data/default_launcher_policy.dart';
import 'package:smart_launcher_app/features/onboarding/data/onboarding_store.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/widgets/set_default_page.dart';

/// Re-prompts non-default users on app return and Discover → Home. Preserves
/// the navigator and coalesces requests into one screen. The remote forced
/// policy still prevents dismissal; normal reminders can be closed after the
/// role request is declined. First-run setup owns its own role screen.
class DefaultLauncherGate extends StatefulWidget {
  const DefaultLauncherGate({super.key, required this.child});

  final Widget child;

  @override
  State<DefaultLauncherGate> createState() => _DefaultLauncherGateState();
}

class _DefaultLauncherGateState extends State<DefaultLauncherGate>
    with WidgetsBindingObserver {
  StreamSubscription<Object?>? _policy;
  StreamSubscription<void>? _requests;
  bool _backgrounded = false;
  bool _blocked = false;
  bool _reminderPending = false;
  int _check = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _policy = DefaultLauncherPolicy.changes.listen((_) => _evaluate());
    _requests = DefaultLauncherPolicy.promptRequests.listen(
      (_) => _evaluate(remind: true),
    );
    unawaited(DefaultLauncherPolicy.loadDeveloperPreference());
    _evaluate(remind: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _policy?.cancel();
    _requests?.cancel();
    LauncherAds.defaultPromptVisible = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The role can change in Android's dialog or another launcher's settings.
    if (state == AppLifecycleState.paused) _backgrounded = true;
    if (state == AppLifecycleState.resumed) {
      final remind = _backgrounded && !_blocked;
      _backgrounded = false;
      _evaluate(remind: remind);
    }
  }

  Future<void> _evaluate({bool remind = false}) async {
    final check = ++_check;
    _reminderPending = _reminderPending || remind;
    final enforce =
        (DefaultLauncherPolicy.forced || _reminderPending || _blocked) &&
        OnboardingStore.isSetupCompletedSync;
    if (enforce) LauncherAds.defaultPromptVisible = true;
    final blocked =
        enforce &&
        !await LauncherService.isDefaultLauncher().timeout(
          const Duration(seconds: 1),
          onTimeout: () => true,
        );
    if (!mounted || check != _check) return;
    if (!blocked) _reminderPending = false;
    LauncherAds.defaultPromptVisible = blocked;
    setState(() => _blocked = blocked);
  }

  void _dismiss() {
    if (DefaultLauncherPolicy.forced) return;
    ++_check;
    _reminderPending = false;
    LauncherAds.defaultPromptVisible = false;
    setState(() => _blocked = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: _blocked,
          child: TickerMode(enabled: !_blocked, child: widget.child),
        ),
        if (_blocked)
          _ForcedDefaultView(
            forced: DefaultLauncherPolicy.forced,
            onDismiss: _dismiss,
            onRoleChanged: () => _evaluate(),
          ),
      ],
    );
  }
}

class _ForcedDefaultView extends StatefulWidget {
  const _ForcedDefaultView({
    required this.forced,
    required this.onDismiss,
    required this.onRoleChanged,
  });
  final bool forced;
  final VoidCallback onDismiss;
  final VoidCallback onRoleChanged;

  @override
  State<_ForcedDefaultView> createState() => _ForcedDefaultViewState();
}

class _ForcedDefaultViewState extends State<_ForcedDefaultView>
    with WidgetsBindingObserver {
  bool _requestInFlight = false;
  bool _asked = false;
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Granting the role lifts the gate and removes this view; still being
    // here a moment after coming back means the user didn't grant it.
    if (state != AppLifecycleState.resumed || !_asked) return;
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      widget.onRoleChanged();
      setState(() => _showError = true);
    });
  }

  Future<void> _request() async {
    if (_requestInFlight) return;
    _asked = true;
    setState(() {
      _requestInFlight = true;
      _showError = false;
    });
    AppAnalytics.onboardingDefaultRequested();
    final launched = await LauncherService.requestHomeRole();
    if (!mounted) return;
    widget.onRoleChanged();
    setState(() {
      _requestInFlight = false;
      if (!launched) _showError = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: SetDefaultPage(
          requestInFlight: _requestInFlight,
          onSetDefault: _request,
          showNotDefaultError: _showError && !_requestInFlight,
          onClose: !widget.forced && _showError ? widget.onDismiss : null,
        ),
      ),
    );
  }
}
