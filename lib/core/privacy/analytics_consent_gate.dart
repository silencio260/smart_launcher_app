import 'package:flutter/material.dart';
import 'package:genrevibes_analytics/genrevibes_analytics.dart';
import 'package:smart_launcher_app/bootstrap/app_runtime.dart';
import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/config/app_env.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';

/// Asks once, on the first launch after install or upgrade, whether the
/// launcher may collect analytics.
///
/// Until it is answered the analytics pipeline stays silent and replay never
/// starts, so the prompt is the thing that turns collection on rather than a
/// notice about collection already happening. Declining is a first-class
/// answer, not a "maybe later": it is stored and applied like any other.
class AnalyticsConsentGate extends StatefulWidget {
  /// Wraps the app's first screen.
  const AnalyticsConsentGate({super.key, required this.child});

  /// The screen shown behind the prompt.
  final Widget child;

  @override
  State<AnalyticsConsentGate> createState() => _AnalyticsConsentGateState();
}

class _AnalyticsConsentGateState extends State<AnalyticsConsentGate> {
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAsk());
  }

  Future<void> _maybeAsk() async {
    if (_asked || !mounted) return;
    if (!sl.isRegistered<AppRuntime>()) return;
    final runtime = sl<AppRuntime>();
    if (!runtime.needsConsentPrompt) return;
    _asked = true;
    final granted = await showAnalyticsConsentDialog(context);
    if (granted == null || !mounted) return;
    await runtime.setAnalyticsConsent(
      granted ? AnalyticsConsent.granted : AnalyticsConsent.denied,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Shows the consent question. Returns null only if it was dismissed without
/// an answer, in which case it is asked again on the next launch.
Future<bool?> showAnalyticsConsentDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Help improve the launcher?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'We can collect anonymous usage data — which features are opened '
            'and how the launcher performs — to decide what to fix and build '
            'next. It never includes your app list, search text, or anything '
            'kept in Vault, App Lock or File Locker.',
          ),
          const SizedBox(height: 12),
          const Text('You can change this any time in Settings → Privacy.'),
          const SizedBox(height: 8),
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () =>
                LauncherService.launchUrl(AppEnv.privacyPolicyUrl),
            child: const Text('Read the privacy policy'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text("Don't allow"),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Allow'),
        ),
      ],
    ),
  );
}
