import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class SmartspaceCard extends StatefulWidget {
  const SmartspaceCard({super.key});

  @override
  State<SmartspaceCard> createState() => _SmartspaceCardState();
}

class _SmartspaceCardState extends State<SmartspaceCard> {
  static const _calendar =
      MethodChannel('com.genrevibes.smartlauncher/calendar');
  static const _alarm = MethodChannel('com.genrevibes.smartlauncher/alarm');

  _CardData? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final event = await _calendar.invokeMethod<Map>('getNextEvent');
      if (event != null && mounted) {
        final dtStart = event['dtStart'] as int?;
        if (dtStart != null) {
          final dt = DateTime.fromMillisecondsSinceEpoch(dtStart);
          final diff = dt.difference(DateTime.now());
          if (diff.inMinutes <= 30 && diff.inMinutes >= 0) {
            setState(() => _data = _CardData(
                  icon: Icons.event,
                  text: event['title'] as String? ?? 'Event',
                  subtitle: DateFormat('h:mm a').format(dt),
                ));
            return;
          }
        }
      }
    } catch (_) {}

    try {
      final alarm = await _alarm.invokeMethod<Map>('getNextAlarm');
      if (alarm != null && mounted) {
        final triggerTime = alarm['triggerTime'] as int?;
        if (triggerTime != null) {
          final dt = DateTime.fromMillisecondsSinceEpoch(triggerTime);
          setState(() => _data = _CardData(
                icon: Icons.alarm,
                text: 'Alarm',
                subtitle: DateFormat('h:mm a').format(dt),
              ));
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_data!.icon, color: Colors.white70, size: 16),
          const SizedBox(width: 6),
          Text(
            '${_data!.text}  ${_data!.subtitle}',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _CardData {
  final IconData icon;
  final String text;
  final String subtitle;
  const _CardData(
      {required this.icon, required this.text, required this.subtitle});
}
