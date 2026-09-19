import 'package:flutter/material.dart';
import 'package:genrevibes_analytics/genrevibes_analytics.dart';
import 'package:smart_launcher_app/bootstrap/app_runtime.dart';
import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/config/app_env.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';

/// Lets the user change the analytics answer they gave at first launch.
///
/// One switch drives everything: event delivery to Firebase and Mixpanel,
/// provider-side collection, and whether this device can record session
/// replay. Crash reports are listed separately because they carry no product
/// analytics and keep the launcher fixable.
class PrivacySettingsScreen extends StatefulWidget {
  /// Creates the privacy settings page.
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool _busy = false;

  AppRuntime? get _runtime =>
      sl.isRegistered<AppRuntime>() ? sl<AppRuntime>() : null;

  Future<void> _set(bool granted) async {
    final runtime = _runtime;
    if (runtime == null || _busy) return;
    setState(() => _busy = true);
    await runtime.setAnalyticsConsent(
      granted ? AnalyticsConsent.granted : AnalyticsConsent.denied,
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _runtime;
    final granted = runtime?.consent == AnalyticsConsent.granted;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListenableBuilder(
        listenable: runtime ?? ValueNotifier<int>(0),
        builder: (context, _) => ListView(
          children: [
            SwitchListTile(
              title: const Text('Share anonymous usage data'),
              subtitle: const Text(
                'Which features are opened and how the launcher performs. '
                'Never your app list, searches, or anything in Vault, App '
                'Lock or File Locker.',
              ),
              value: granted,
              onChanged: runtime == null || _busy ? null : _set,
            ),
            const Divider(),
            const ListTile(
              leading: Icon(Icons.bug_report_outlined),
              title: Text('Crash reports'),
              subtitle: Text(
                'Always on. Crash reports contain no usage data and are how '
                'launcher freezes and crashes get fixed.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy Policy'),
              onTap: () => LauncherService.launchUrl(AppEnv.privacyPolicyUrl),
            ),
          ],
        ),
      ),
    );
  }
}
