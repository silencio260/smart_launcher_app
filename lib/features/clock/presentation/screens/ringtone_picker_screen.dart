import 'package:flutter/material.dart';

import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/core/widgets/mini_app_chrome.dart';

/// Lets the user choose an alarm sound: the device default, a system alarm
/// tone (native ringtone picker), or any audio file on the device (SAF). The
/// result is returned as `{uri, title}` where a null `uri` means "default".
class RingtonePickerScreen extends StatefulWidget {
  final String? currentUri;
  final String currentTitle;

  const RingtonePickerScreen({
    super.key,
    required this.currentUri,
    required this.currentTitle,
  });

  @override
  State<RingtonePickerScreen> createState() => _RingtonePickerScreenState();
}

class _RingtonePickerScreenState extends State<RingtonePickerScreen> {
  late String? _uri = widget.currentUri;
  late String _title = widget.currentTitle;
  bool _previewing = false;

  @override
  void dispose() {
    LauncherService.stopPreview();
    super.dispose();
  }

  Future<void> _togglePreview() async {
    if (_previewing) {
      await LauncherService.stopPreview();
      setState(() => _previewing = false);
    } else {
      await LauncherService.previewTone(_uri);
      setState(() => _previewing = true);
    }
  }

  Future<void> _pickSystem() async {
    await LauncherService.stopPreview();
    final result = await LauncherService.pickSystemRingtone(currentUri: _uri);
    if (result == null || !mounted) return;
    Navigator.pop(context, {'uri': result['uri'], 'title': result['title']});
  }

  Future<void> _pickCustom() async {
    await LauncherService.stopPreview();
    final result = await LauncherService.pickCustomAudio();
    if (result == null || !mounted) return;
    Navigator.pop(context, {'uri': result['uri'], 'title': result['title']});
  }

  void _useDefault() {
    setState(() {
      _uri = null;
      _title = 'Default';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MiniAppScaffold(
      title: 'Alarm sound',
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, {'uri': _uri, 'title': _title}),
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          child: const Text('Done'),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          MiniCard(
            child: Row(
              children: [
                const Icon(Icons.music_note, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Selected',
                          style: TextStyle(color: miniAppMuted, fontSize: 13)),
                      Text(_title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _togglePreview,
                  icon: Icon(
                    _previewing
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _OptionTile(
            icon: Icons.notifications_active_outlined,
            title: 'Default alarm sound',
            selected: _uri == null,
            onTap: _useDefault,
          ),
          _OptionTile(
            icon: Icons.library_music_outlined,
            title: 'System alarm sounds…',
            onTap: _pickSystem,
          ),
          _OptionTile(
            icon: Icons.folder_open_outlined,
            title: 'Choose audio file…',
            onTap: _pickCustom,
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: Colors.white),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      trailing: selected
          ? const Icon(Icons.check, color: Colors.white)
          : const Icon(Icons.chevron_right, color: miniAppMuted),
      onTap: onTap,
    );
  }
}
