import 'package:flutter/material.dart';

import '../../../data/mini_app_repositories.dart';
import '../../../services/launcher_service.dart';
import '../clock/clock_theme.dart';
import '../mini_app_chrome.dart';
import '../mini_app_kit.dart';
import 'app_hider_lock_screen.dart';

/// App Hider settings, mirroring the Vault / App Lock settings screens (change
/// passcode, switch PIN/Pattern, toggle fingerprint, auto-lock) plus the bit
/// unique to App Hider — the home-screen disguise — and a guarded turn-off.
class AppHiderSettingsScreen extends StatefulWidget {
  const AppHiderSettingsScreen({super.key});

  @override
  State<AppHiderSettingsScreen> createState() => _AppHiderSettingsScreenState();
}

class _AppHiderSettingsScreenState extends State<AppHiderSettingsScreen> {
  final _sec = AppHiderSecurityRepository();
  final _policy = MiniAppPolicyRepository();

  static const _autoLockSteps = <int, String>{
    0: 'Immediately',
    60000: 'After 1 minute',
    300000: 'After 5 minutes',
  };

  static const _disguises = <String>[
    'App Hider',
    'Calculator',
    'Notes',
    'Weather',
    'Browser',
  ];

  Future<void> _changePasscode({String? type}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => AppHiderLockScreen(
          security: _sec,
          forceSetup: true,
          initialType: type,
          onUnlocked: () => Navigator.of(context).pop(true),
          onCancel: () => Navigator.of(context).pop(false),
        ),
      ),
    );
    if (changed == true && mounted) setState(() {});
  }

  void _cycleAutoLock() {
    final keys = _autoLockSteps.keys.toList();
    final i = keys.indexOf(_sec.autoLockMs);
    final next = keys[(i + 1) % keys.length];
    _sec.setAutoLockMs(next);
    setState(() {});
  }

  Future<void> _setDisguise(String value) async {
    await _policy.setDisguise(value);
    await LauncherService.setAppHiderDisguise(value);
    if (mounted) setState(() {});
  }

  Future<void> _turnOff() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: clockThemeOf(context),
        child: AlertDialog(
          backgroundColor: miniAppSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('Turn off passcode?',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: const Text(
            'App Hider will open without asking for your PIN or pattern. Your '
            'hidden apps stay hidden. You can set a passcode again any time.',
            style: TextStyle(color: miniAppMuted, height: 1.3),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:
                  const Text('Cancel', style: TextStyle(color: miniAppMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Turn off',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    await _sec.clear();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isPin = _sec.type == AppHiderSecurityRepository.typePin;
    return MiniAppScaffold(
      title: 'App Hider settings',
      child: Theme(
        data: clockThemeOf(context),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            const MiniSectionHeader('Security'),
            MiniFeatureRow(
              icon: Icons.password_outlined,
              iconColor: Colors.white,
              title: 'Change passcode',
              subtitle: 'Set a new ${isPin ? 'PIN' : 'pattern'}',
              onTap: _changePasscode,
            ),
            const SizedBox(height: 12),
            MiniFeatureRow(
              icon: Icons.tune,
              iconColor: Colors.white,
              title: 'Passcode type',
              subtitle: 'Unlock with a PIN or a pattern',
              trailing: Text(
                isPin ? 'PIN' : 'Pattern',
                style: const TextStyle(
                    color: miniAppMuted, fontWeight: FontWeight.w700),
              ),
              onTap: () => _changePasscode(
                type: isPin
                    ? AppHiderSecurityRepository.typePattern
                    : AppHiderSecurityRepository.typePin,
              ),
            ),
            const SizedBox(height: 12),
            MiniFeatureRow(
              icon: Icons.fingerprint,
              iconColor: Colors.white,
              title: 'Fingerprint unlock',
              subtitle: 'Open with your device fingerprint or lock',
              trailing: Switch(
                value: _sec.biometricEnabled,
                onChanged: (value) async {
                  await _sec.setBiometricEnabled(value);
                  setState(() {});
                },
              ),
            ),
            const SizedBox(height: 18),
            const MiniSectionHeader('Disguise icon'),
            RoundCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pick how App Hider appears on the home screen. The disguise '
                    'is staged through Android aliases.',
                    style: TextStyle(color: miniAppMuted, height: 1.3),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final option in _disguises)
                        _DisguiseChip(
                          label: option,
                          selected: _policy.disguise == option,
                          onTap: () => _setDisguise(option),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const MiniSectionHeader('Auto-lock'),
            MiniFeatureRow(
              icon: Icons.lock_clock_outlined,
              iconColor: Colors.white,
              title: 'Lock App Hider',
              subtitle: 'Re-ask for the passcode when you reopen it',
              trailing: Text(
                _autoLockSteps[_sec.autoLockMs] ?? 'Immediately',
                style: const TextStyle(
                    color: miniAppMuted, fontWeight: FontWeight.w700),
              ),
              onTap: _cycleAutoLock,
            ),
            const SizedBox(height: 26),
            MiniFeatureRow(
              icon: Icons.lock_open_outlined,
              iconColor: Colors.redAccent,
              title: 'Turn off passcode',
              subtitle: 'Open App Hider without a PIN or pattern',
              onTap: _turnOff,
            ),
          ],
        ),
      ),
    );
  }
}

class _DisguiseChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DisguiseChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : miniAppSurface2,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
