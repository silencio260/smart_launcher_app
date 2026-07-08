import 'package:flutter/material.dart';

import 'package:smart_launcher_app/features/app_hider/presentation/screens/app_hider_onboarding.dart';
import 'package:smart_launcher_app/features/app_lock/presentation/screens/app_lock_onboarding.dart';
import 'package:smart_launcher_app/features/clock/presentation/screens/clock_onboarding.dart';
import 'package:smart_launcher_app/features/file_locker/presentation/screens/file_locker_onboarding.dart';
import 'package:smart_launcher_app/features/onboarding/data/onboarding_store.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/screens/onboarding_screen.dart';

/// Dev View harness for quickly inspecting every onboarding flow in one place.
///
/// The launcher first-run flow and each mini-app's first-open intro can be
/// previewed live; resets make them re-appear on the next open / cold start.
class OnboardingDebugScreen extends StatefulWidget {
  const OnboardingDebugScreen({super.key});

  @override
  State<OnboardingDebugScreen> createState() => _OnboardingDebugScreenState();
}

class _OnboardingDebugScreenState extends State<OnboardingDebugScreen> {
  bool _loading = true;
  bool _completed = false;
  bool _nudgeDismissed = false;
  final _miniAppState = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final completed = await OnboardingStore.isCompleted();
    final nudgeDismissed = await OnboardingStore.isNudgeDismissed();
    final miniApps = <String, bool>{};
    for (final flow in _miniAppFlows) {
      miniApps[flow.id] = await OnboardingStore.isMiniAppOnboarded(flow.id);
    }
    if (!mounted) return;
    setState(() {
      _completed = completed;
      _nudgeDismissed = nudgeDismissed;
      _miniAppState
        ..clear()
        ..addAll(miniApps);
      _loading = false;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Onboarding')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _SectionHeader('Launcher first-run'),
          if (_loading)
            const ListTile(title: Text('Loading state…'))
          else ...[
            _StatusTile(label: 'Onboarding completed', value: _completed),
            _StatusTile(
              label: 'Set-default nudge dismissed',
              value: _nudgeDismissed,
            ),
          ],
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('Preview launcher onboarding'),
            subtitle: const Text(
              'Walk all screens without changing the real default launcher',
            ),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const OnboardingScreen(previewMode: true),
                ),
              );
              if (mounted) _load();
            },
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Reset onboarding flag'),
            subtitle: const Text('Show the first-run flow on the next launch'),
            onTap: () async {
              await OnboardingStore.resetCompleted();
              _toast('Onboarding will show on next launch');
              _load();
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Reset set-default nudge'),
            subtitle: const Text('Re-show the home-screen reminder pill'),
            onTap: () async {
              await OnboardingStore.resetNudge();
              _toast('Nudge reset — returns to home to see it');
              _load();
            },
          ),
          const _SectionHeader('Mini-app first-open intros'),
          for (final flow in _miniAppFlows)
            ListTile(
              leading: Icon(flow.icon),
              title: Text(flow.title),
              subtitle: Text(
                (_miniAppState[flow.id] ?? false) ? 'Seen' : 'Not seen yet',
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Preview',
                    icon: const Icon(Icons.play_circle_outline),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => flow.build(
                          () => Navigator.of(context).maybePop(),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reset',
                    icon: const Icon(Icons.restart_alt),
                    onPressed: () async {
                      await OnboardingStore.resetMiniAppOnboarded(flow.id);
                      _toast('${flow.title} intro will show on next open');
                      _load();
                    },
                  ),
                ],
              ),
            ),
          const _SectionHeader('Location-based flows'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Discover and Good Morning request location in-context on first '
              'use rather than via a separate intro.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// A previewable mini-app intro. [build] wires both the continue and back
/// callbacks to the same pop so preview never mutates the real flag.
class _MiniAppFlow {
  final String id;
  final String title;
  final IconData icon;
  final Widget Function(VoidCallback pop) build;

  const _MiniAppFlow({
    required this.id,
    required this.title,
    required this.icon,
    required this.build,
  });
}

final _miniAppFlows = <_MiniAppFlow>[
  _MiniAppFlow(
    id: 'app_locker',
    title: 'App Lock',
    icon: Icons.lock_outline,
    build: (pop) => AppLockOnboarding(onContinue: pop, onBack: pop),
  ),
  _MiniAppFlow(
    id: 'app_hider',
    title: 'App Hider',
    icon: Icons.visibility_off_outlined,
    build: (pop) => AppHiderOnboarding(onContinue: pop, onBack: pop),
  ),
  _MiniAppFlow(
    id: 'file_locker',
    title: 'File Locker',
    icon: Icons.folder_outlined,
    build: (pop) => FileLockerOnboarding(onContinue: pop, onBack: pop),
  ),
  _MiniAppFlow(
    id: 'alarm_clock',
    title: 'Clock',
    icon: Icons.alarm_outlined,
    build: (pop) => ClockOnboarding(onContinue: pop, onBack: pop),
  ),
];

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.label, required this.value});

  final String label;
  final bool value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        value ? Icons.check_circle_outline : Icons.radio_button_unchecked,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(label),
      trailing: Text(value ? 'true' : 'false'),
    );
  }
}
