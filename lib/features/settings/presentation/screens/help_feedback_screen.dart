import 'package:flutter/material.dart';

import '../../config/support_links.dart';
import '../../models/launcher_feature.dart';
import '../../services/launcher_service.dart';

/// Help & Feedback sub-page reached from the Support section of Launcher
/// Settings. Mirrors the three common exit/help paths a launcher user looks
/// for: switch back to their old home screen, send feedback, and find out how
/// to uninstall.
class HelpFeedbackScreen extends StatelessWidget {
  const HelpFeedbackScreen({super.key});

  Future<void> _giveFeedback(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: SupportLinks.feedbackEmail,
      query: 'subject=${Uri.encodeComponent(SupportLinks.feedbackSubject)}',
    );
    final ok = await LauncherService.launchUrl(uri.toString());
    if (!context.mounted) return;
    if (!ok) {
      _toast(context, 'No email app found to send feedback');
    }
  }

  Future<void> _restoreHomescreen(BuildContext context) async {
    final ok = await LauncherService.openHomeSettings();
    if (!context.mounted) return;
    if (!ok) {
      _toast(context, "Couldn't open the Home app settings");
    }
  }

  void _showUninstallHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('How to uninstall'),
        content: const Text(
          'To remove Smart Launcher:\n\n'
          '1. Open the App info page (tap "Open app info" below).\n'
          '2. Tap Uninstall.\n\n'
          'If Smart Launcher is still your default home app, set your '
          'preferred launcher as default first so your phone has a home '
          'screen to return to.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              LauncherService.openAppSettings(LauncherFeature.launcherPackage);
            },
            child: const Text('Open app info'),
          ),
        ],
      ),
    );
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Feedback')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('You might want to:'),
          ),
          _HelpTile(
            icon: Icons.restart_alt,
            title: 'I want to restore my previous system Homescreen.',
            onTap: () => _restoreHomescreen(context),
          ),
          _HelpTile(
            icon: Icons.mark_email_unread_outlined,
            title: 'I still need to give feedback.',
            onTap: () => _giveFeedback(context),
          ),
          _HelpTile(
            icon: Icons.delete_outline,
            title: 'How to Uninstall',
            onTap: () => _showUninstallHelp(context),
          ),
        ],
      ),
    );
  }
}

class _HelpTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _HelpTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: onTap,
    );
  }
}
