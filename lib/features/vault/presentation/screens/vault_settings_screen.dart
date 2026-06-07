import 'package:flutter/material.dart';

import 'package:smart_launcher_app/core/storage/mini_app_repositories.dart';
import 'package:smart_launcher_app/features/clock/presentation/clock_theme.dart';
import 'package:smart_launcher_app/core/widgets/mini_app_chrome.dart';
import 'package:smart_launcher_app/core/widgets/mini_app_kit.dart';
import 'package:smart_launcher_app/features/vault/presentation/screens/vault_lock_screen.dart';

/// Minimal vault settings, styled after the App Lock reference but monochrome:
/// change passcode, switch PIN/Pattern, toggle fingerprint, set auto-lock.
class VaultSettingsScreen extends StatefulWidget {
  const VaultSettingsScreen({super.key});

  @override
  State<VaultSettingsScreen> createState() => _VaultSettingsScreenState();
}

class _VaultSettingsScreenState extends State<VaultSettingsScreen> {
  final _sec = VaultSecurityRepository();

  static const _autoLockSteps = <int, String>{
    0: 'Immediately',
    60000: 'After 1 minute',
    300000: 'After 5 minutes',
  };

  Future<void> _changePasscode({String? type}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => VaultLockScreen(
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

  @override
  Widget build(BuildContext context) {
    final isPin = _sec.type == VaultSecurityRepository.typePin;
    return MiniAppScaffold(
      title: 'Vault settings',
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
                    ? VaultSecurityRepository.typePattern
                    : VaultSecurityRepository.typePin,
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
            const MiniSectionHeader('Privacy'),
            MiniFeatureRow(
              icon: Icons.hide_image_outlined,
              iconColor: Colors.white,
              title: 'Remove originals after import',
              subtitle: 'Delete imported files from your gallery',
              trailing: Switch(
                value: _sec.removeOriginals,
                onChanged: (value) async {
                  await _sec.setRemoveOriginals(value);
                  setState(() {});
                },
              ),
            ),
            const SizedBox(height: 18),
            const MiniSectionHeader('Auto-lock'),
            MiniFeatureRow(
              icon: Icons.lock_clock_outlined,
              iconColor: Colors.white,
              title: 'Lock the vault',
              subtitle: 'Re-ask for the passcode when you reopen it',
              trailing: Text(
                _autoLockSteps[_sec.autoLockMs] ?? 'Immediately',
                style: const TextStyle(
                    color: miniAppMuted, fontWeight: FontWeight.w700),
              ),
              onTap: _cycleAutoLock,
            ),
          ],
        ),
      ),
    );
  }
}
