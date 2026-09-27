import 'dart:async';

import 'package:flutter/material.dart';

import 'package:smart_launcher_app/core/analytics/app_events.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/features/onboarding/data/default_launcher_policy.dart';
import 'package:smart_launcher_app/features/onboarding/data/onboarding_store.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/widgets/set_default_page.dart';

/// Blocks the launcher while the remote `launcher_force_default` switch is on
/// and another app holds the home role. Wraps the app's navigator (from
/// `MaterialApp.builder`) and keeps it alive underneath, so nothing reloads
/// when the block lifts. First-run setup enforces the role on its own screen.
class DefaultLauncherGate extends StatefulWidget {
  const DefaultLauncherGate({super.key, required this.child});

  final Widget child;

  @override
  State<DefaultLauncherGate> createState() => _DefaultLauncherGateState();
}

class _DefaultLauncherGateState extends State<DefaultLauncherGate>
    with WidgetsBindingObserver {
  StreamSubscription<Object?>? _policy;
  bool _blocked = false;
  int _check = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _policy = DefaultLauncherPolicy.changes.listen((_) => _evaluate());
    _evaluate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _policy?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The role can change in Android's dialog or another launcher's settings.
    if (state == AppLifecycleState.resumed) _evaluate();
  }

  Future<void> _evaluate() async {
    final check = ++_check;
    // Only ask the platform when the switch is on (the common case skips it).
    final enforce =
        DefaultLauncherPolicy.forced && OnboardingStore.isSetupCompletedSync;
    final blocked = enforce && !await LauncherService.isDefaultLauncher();
    if (!mounted || check != _check || blocked == _blocked) return;
    setState(() => _blocked = blocked);
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
          // Its own overlay: this sits above the app's navigator.
          Overlay(
            initialEntries: [
              OverlayEntry(builder: (_) => const _ForcedDefaultView()),
            ],
          ),
      ],
    );
  }
}

class _ForcedDefaultView extends StatefulWidget {
  const _ForcedDefaultView();

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
      if (mounted) setState(() => _showError = true);
    });
  }

  Future<void> _request() async {
    if (_requestInFlight) return;
    _asked = true;
    setState(() => _requestInFlight = true);
    AppAnalytics.onboardingDefaultRequested();
    await LauncherService.requestHomeRole();
    if (mounted) setState(() => _requestInFlight = false);
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
        ),
      ),
    );
  }
}
