import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../../../data/mini_app_repositories.dart';
import '../../../services/clock_service.dart';
import '../../../services/launcher_service.dart';
import '../mini_app_chrome.dart';
import 'ringtone_picker_screen.dart';

/// Full create/edit screen for a single alarm. Returns true if the alarm list
/// changed (saved or deleted).
class AlarmEditScreen extends StatefulWidget {
  final ClockRepository repo;

  /// Existing alarm to edit, or null to create a new one.
  final ClockAlarmRecord? existing;

  const AlarmEditScreen({super.key, required this.repo, this.existing});

  @override
  State<AlarmEditScreen> createState() => _AlarmEditScreenState();
}

class _AlarmEditScreenState extends State<AlarmEditScreen> {
  static const _uuid = Uuid();
  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  late TimeOfDay _time;
  late TextEditingController _label;
  late Set<int> _repeatDays;
  late bool _vibrate;
  late bool _gradualVolume;
  late int _snoozeMinutes;
  late int _autoSilenceMinutes;
  String? _ringtoneUri;
  late String _ringtoneTitle;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _time = a == null
        ? TimeOfDay.now()
        : TimeOfDay(hour: a.hour, minute: a.minute);
    _label = TextEditingController(text: a?.label ?? 'Alarm');
    _repeatDays = {...(a?.repeatDays ?? const <int>[])};
    _vibrate = a?.vibrate ?? true;
    _gradualVolume = a?.graduallyIncreaseVolume ?? false;
    _snoozeMinutes = a?.snoozeMinutes ?? 5;
    _autoSilenceMinutes = a?.autoSilenceMinutes ?? 10;
    _ringtoneUri = a?.ringtoneUri;
    _ringtoneTitle = a?.ringtoneTitle ?? 'Default';
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  ClockAlarmRecord _build() {
    final repeat = _repeatDays.toList()..sort();
    return ClockAlarmRecord(
      id: widget.existing?.id ?? _uuid.v4(),
      hour: _time.hour,
      minute: _time.minute,
      label: _label.text.trim().isEmpty ? 'Alarm' : _label.text.trim(),
      enabled: true,
      repeatDays: repeat,
      vibrate: _vibrate,
      snoozeMinutes: _snoozeMinutes,
      ringtoneUri: _ringtoneUri,
      ringtoneTitle: _ringtoneTitle,
      graduallyIncreaseVolume: _gradualVolume,
      autoSilenceMinutes: _autoSilenceMinutes,
      createdAt: widget.existing?.createdAt ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _save() async {
    final record = _build();
    // An alarm that can't post a notification can't surface its ring UI on
    // Android 13+, so make sure we've asked before scheduling.
    await _ensureNotificationPermission();
    final scheduled = await widget.repo.saveAndSchedule(record);
    if (!mounted) return;
    if (!scheduled) {
      final granted = await _promptExactAlarm();
      if (granted) await widget.repo.scheduleAlarm(record);
    }
    final next = widget.repo.nextRing(record);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alarm set ${ClockService.humanizeUntil(next)}')),
      );
      Navigator.pop(context, true);
    }
  }

  /// Asks for POST_NOTIFICATIONS the first time it's needed. If the user has
  /// permanently denied it, the request is a no-op and the Alarms-tab setup
  /// banner steers them to settings instead.
  Future<void> _ensureNotificationPermission() async {
    final status = await Permission.notification.status;
    if (!status.isGranted && !status.isPermanentlyDenied) {
      await Permission.notification.request();
    }
  }

  Future<bool> _promptExactAlarm() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allow exact alarms'),
        content: const Text(
          'To ring at the exact time, this launcher needs permission to '
          'schedule exact alarms. Open settings to allow it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (go == true) {
      await LauncherService.requestExactAlarmAccess();
      return LauncherService.canScheduleExactAlarms();
    }
    return false;
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete alarm?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.repo.deleteAlarm(id);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _pickRingtone() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => RingtonePickerScreen(
          currentUri: _ringtoneUri,
          currentTitle: _ringtoneTitle,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _ringtoneUri = result['uri'] as String?;
      _ringtoneTitle = (result['title'] as String?) ?? 'Default';
    });
  }

  Future<void> _pickFromOptions({
    required String title,
    required List<int> options,
    required int current,
    required String Function(int) labelOf,
    required ValueChanged<int> onSelected,
  }) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: miniAppSurface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              ListTile(
                title: Text(labelOf(option)),
                trailing: option == current
                    ? const Icon(Icons.check, color: miniAppAccent)
                    : null,
                onTap: () => Navigator.pop(context, option),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    return MiniAppScaffold(
      title: _isNew ? 'New alarm' : 'Edit alarm',
      actions: [
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
        children: [
          SizedBox(
            height: 180,
            child: CupertinoTheme(
              data: const CupertinoThemeData(brightness: Brightness.dark),
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                use24hFormat: MediaQuery.of(context).alwaysUse24HourFormat,
                initialDateTime:
                    DateTime(2024, 1, 1, _time.hour, _time.minute),
                onDateTimeChanged: (value) =>
                    setState(() => _time = TimeOfDay.fromDateTime(value)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _RepeatPicker(
            selected: _repeatDays,
            labels: _dayLabels,
            onToggle: (day) => setState(() {
              if (!_repeatDays.add(day)) _repeatDays.remove(day);
            }),
          ),
          const SizedBox(height: 8),
          Text(
            ClockService.repeatLabel(_repeatDays.toList()..sort()),
            style: const TextStyle(color: miniAppMuted),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _label,
            decoration: const InputDecoration(
              labelText: 'Label',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          MiniCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _TapRow(
                  icon: Icons.music_note,
                  label: 'Sound',
                  value: _ringtoneTitle,
                  onTap: _pickRingtone,
                ),
                const Divider(height: 1, color: miniAppSurface2),
                _SwitchRow(
                  icon: Icons.vibration,
                  label: 'Vibrate',
                  value: _vibrate,
                  onChanged: (v) => setState(() => _vibrate = v),
                ),
                const Divider(height: 1, color: miniAppSurface2),
                _SwitchRow(
                  icon: Icons.volume_up_outlined,
                  label: 'Increase volume gradually',
                  value: _gradualVolume,
                  onChanged: (v) => setState(() => _gradualVolume = v),
                ),
                const Divider(height: 1, color: miniAppSurface2),
                _TapRow(
                  icon: Icons.snooze,
                  label: 'Snooze',
                  value: '$_snoozeMinutes min',
                  onTap: () => _pickFromOptions(
                    title: 'Snooze duration',
                    options: const [1, 5, 10, 15, 20, 30],
                    current: _snoozeMinutes,
                    labelOf: (m) => '$m min',
                    onSelected: (m) => setState(() => _snoozeMinutes = m),
                  ),
                ),
                const Divider(height: 1, color: miniAppSurface2),
                _TapRow(
                  icon: Icons.timer_off_outlined,
                  label: 'Silence after',
                  value: _autoSilenceMinutes == 0
                      ? 'Never'
                      : '$_autoSilenceMinutes min',
                  onTap: () => _pickFromOptions(
                    title: 'Silence after',
                    options: const [0, 1, 5, 10, 15, 30],
                    current: _autoSilenceMinutes,
                    labelOf: (m) => m == 0 ? 'Never' : '$m min',
                    onSelected: (m) =>
                        setState(() => _autoSilenceMinutes = m),
                  ),
                ),
              ],
            ),
          ),
          if (!_isNew) ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              label: const Text('Delete alarm',
                  style: TextStyle(color: Colors.redAccent)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RepeatPicker extends StatelessWidget {
  final Set<int> selected;
  final List<String> labels;
  final ValueChanged<int> onToggle;

  const _RepeatPicker({
    required this.selected,
    required this.labels,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i++)
          GestureDetector(
            onTap: () => onToggle(i + 1),
            child: CircleAvatar(
              radius: 21,
              backgroundColor:
                  selected.contains(i + 1) ? miniAppAccent : miniAppSurface,
              child: Text(
                labels[i].substring(0, 1),
                style: TextStyle(
                  color:
                      selected.contains(i + 1) ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TapRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _TapRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: miniAppAccent),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: miniAppMuted)),
          ),
          const Icon(Icons.chevron_right, color: miniAppMuted),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon, color: miniAppAccent),
      title: Text(label),
      value: value,
      onChanged: onChanged,
    );
  }
}
