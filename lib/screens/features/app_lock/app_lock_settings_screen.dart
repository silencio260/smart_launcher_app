import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/mini_app_repositories.dart';
import '../../../services/launcher_service.dart';
import '../../../state/launcher_feature_cubit.dart';
import '../clock/clock_theme.dart';
import '../mini_app_chrome.dart';
import '../mini_app_kit.dart';
import 'app_lock_lock_screen.dart';

/// App Lock settings, mirroring the Vault's settings screen (change passcode,
/// switch PIN/Pattern, toggle fingerprint, auto-lock) plus the bits unique to
/// App Lock: the device permissions it needs and a guarded turn-off.
class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({super.key});

  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen>
    with WidgetsBindingObserver {
  final _sec = AppLockSecurityRepository();

  var _accessibility = false;
  var _overlay = false;

  static const _autoLockSteps = <int, String>{
    0: 'Immediately',
    60000: 'After 1 minute',
    300000: 'After 5 minutes',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the system permission screens: re-check.
    if (state == AppLifecycleState.resumed) _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final accessibility = await LauncherService.isAccessibilityServiceEnabled();
    final overlay = await LauncherService.canDrawOverlays();
    if (!mounted) return;
    setState(() {
      _accessibility = accessibility;
      _overlay = overlay;
    });
  }

  Future<void> _changePasscode({String? type}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => AppLockLockScreen(
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

  Future<void> _turnOff() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: clockThemeOf(context),
        child: AlertDialog(
          backgroundColor: miniAppSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('Turn off App Lock?',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: const Text(
            'Your PIN/pattern is removed and every app is unlocked. You can set '
            'it up again any time.',
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
    final cubit = context.read<LauncherFeatureSettingsCubit>();
    await cubit.update(cubit.state.copyWith(lockedApps: const []));
    await _sec.clear();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isPin = _sec.type == AppLockSecurityRepository.typePin;
    return MiniAppScaffold(
      title: 'App Lock settings',
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
                    ? AppLockSecurityRepository.typePattern
                    : AppLockSecurityRepository.typePin,
              ),
            ),
            const SizedBox(height: 12),
            MiniFeatureRow(
              icon: Icons.fingerprint,
              iconColor: Colors.white,
              title: 'Fingerprint unlock',
              subtitle: 'Unlock apps with your device fingerprint or lock',
              trailing: Switch(
                value: _sec.biometricEnabled,
                onChanged: (value) async {
                  await _sec.setBiometricEnabled(value);
                  setState(() {});
                },
              ),
            ),
            const SizedBox(height: 18),
            const MiniSectionHeader('Auto-lock'),
            MiniFeatureRow(
              icon: Icons.lock_clock_outlined,
              iconColor: Colors.white,
              title: 'Lock App Lock',
              subtitle: 'Re-ask for the passcode when you return here',
              trailing: Text(
                _autoLockSteps[_sec.autoLockMs] ?? 'Immediately',
                style: const TextStyle(
                    color: miniAppMuted, fontWeight: FontWeight.w700),
              ),
              onTap: _cycleAutoLock,
            ),
            const SizedBox(height: 18),
            const MiniSectionHeader('Permissions'),
            MiniFeatureRow(
              icon: Icons.accessibility_new,
              iconColor: Colors.white,
              title: 'App Lock service',
              subtitle: 'Lets the lock screen appear when you open a locked app',
              trailing: _permTrailing(_accessibility),
              onTap: _accessibility
                  ? null
                  : () async {
                      await LauncherService.requestAccessibilityAccess();
                      await _refreshPermissions();
                    },
            ),
            const SizedBox(height: 12),
            MiniFeatureRow(
              icon: Icons.layers_outlined,
              iconColor: Colors.white,
              title: 'Display over apps',
              subtitle: 'Lets the unlock screen show on top of locked apps',
              trailing: _permTrailing(_overlay),
              onTap: _overlay
                  ? null
                  : () async {
                      await LauncherService.requestOverlayPermission();
                      await _refreshPermissions();
                    },
            ),
            const SizedBox(height: 26),
            MiniFeatureRow(
              icon: Icons.lock_open_outlined,
              iconColor: Colors.redAccent,
              title: 'Turn off App Lock',
              subtitle: 'Remove your passcode and unlock all apps',
              onTap: _turnOff,
            ),
          ],
        ),
      ),
    );
  }

  Widget _permTrailing(bool granted) {
    if (granted) {
      return const Icon(Icons.check_circle, color: Colors.white);
    }
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Enable',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        SizedBox(width: 6),
        Icon(Icons.chevron_right, color: miniAppMuted),
      ],
    );
  }
}
