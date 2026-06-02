import 'package:flutter/material.dart';

import '../../../services/launcher_service.dart';
import '../clock/clock_theme.dart';
import '../mini_app_chrome.dart';
import '../mini_app_kit.dart';

/// Guided "turn on protection" screen for App Lock.
///
/// App Lock enforcement is native: an accessibility service detects the
/// foreground app and draws our lock overlay. If that service is off (the most
/// common cause of "it only works in the launcher"), locks never appear
/// device-wide. This screen walks the user through the two required toggles
/// (accessibility service + display-over-apps) plus a recommended battery
/// exemption, deep-linking straight to each, and auto-rechecks on resume.
class AppLockProtectionGuide extends StatefulWidget {
  const AppLockProtectionGuide({super.key});

  @override
  State<AppLockProtectionGuide> createState() => _AppLockProtectionGuideState();
}

class _AppLockProtectionGuideState extends State<AppLockProtectionGuide>
    with WidgetsBindingObserver {
  var _accessibility = false;
  var _overlay = false;
  var _battery = true; // assume exempt until known; this step is non-blocking.

  bool get _ready => _accessibility && _overlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from a system settings screen: re-check so the steps flip to ✓.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final accessibility = await LauncherService.isAccessibilityServiceEnabled();
    final overlay = await LauncherService.canDrawOverlays();
    final battery = await LauncherService.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _accessibility = accessibility;
      _overlay = overlay;
      _battery = battery;
    });
  }

  Future<void> _openAccessibility() async {
    await LauncherService.requestAccessibilityAccess();
    await _refresh();
  }

  Future<void> _openOverlay() async {
    await LauncherService.requestOverlayPermission();
    await _refresh();
  }

  Future<void> _openBattery() async {
    await LauncherService.requestIgnoreBatteryOptimizations();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final warn = accentForFeature('app_locker');
    return MiniAppScaffold(
      title: 'Protection',
      child: Theme(
        data: clockThemeOf(context),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _hero(warn),
            const SizedBox(height: 18),
            const MiniSectionHeader('Required'),
            _stepRow(
              icon: Icons.accessibility_new,
              title: 'App Lock service',
              subtitle:
                  'Find “Smart Launcher Accessibility” and turn it ON. This lets the '
                  'lock screen appear over any locked app, anywhere on your phone.',
              granted: _accessibility,
              onTap: _openAccessibility,
            ),
            const SizedBox(height: 12),
            _stepRow(
              icon: Icons.layers_outlined,
              title: 'Display over apps',
              subtitle: 'Lets the unlock screen show on top of locked apps.',
              granted: _overlay,
              onTap: _openOverlay,
            ),
            const SizedBox(height: 18),
            const MiniSectionHeader('Recommended'),
            _stepRow(
              icon: Icons.battery_saver_outlined,
              title: 'Keep running in the background',
              subtitle:
                  'Set App Lock to “Don’t optimise” so the lock keeps working after '
                  'the screen sleeps or you switch apps.',
              granted: _battery,
              actionLabel: 'Turn on',
              onTap: _openBattery,
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(Color warn) {
    if (_ready) {
      return RoundCard(
        child: Row(
          children: [
            _badge(Icons.verified_user, Colors.white),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Protection is on',
                      style: TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text(
                    'Your locked apps are protected everywhere on this phone.',
                    style: TextStyle(color: miniAppMuted, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RoundCard(
      child: Row(
        children: [
          _badge(Icons.gpp_maybe, warn),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'App Lock is off',
                  style: TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800, color: warn),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Turn on the steps below so your locked apps are protected '
                  'everywhere — not just inside the launcher.',
                  style: TextStyle(color: miniAppMuted, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(IconData icon, Color color) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color, size: 28),
    );
  }

  Widget _stepRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required VoidCallback onTap,
    String actionLabel = 'Enable',
  }) {
    return MiniFeatureRow(
      icon: icon,
      iconColor: Colors.white,
      title: title,
      subtitle: subtitle,
      onTap: granted ? null : onTap,
      trailing: granted
          ? const Icon(Icons.check_circle, color: Colors.white)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(actionLabel,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: miniAppMuted),
              ],
            ),
    );
  }
}
