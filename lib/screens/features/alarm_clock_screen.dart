import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/launcher_service.dart';

class AlarmClockScreen extends StatefulWidget {
  const AlarmClockScreen({super.key});

  @override
  State<AlarmClockScreen> createState() => _AlarmClockScreenState();
}

class _AlarmClockScreenState extends State<AlarmClockScreen> {
  late Future<Map<String, dynamic>?> _nextAlarmFuture;

  @override
  void initState() {
    super.initState();
    _nextAlarmFuture = LauncherService.getNextAlarm();
  }

  void _refresh() {
    setState(() => _nextAlarmFuture = LauncherService.getNextAlarm());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alarm Clock')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<Map<String, dynamic>?>(
            future: _nextAlarmFuture,
            builder: (context, snapshot) {
              final alarm = snapshot.data;
              final trigger = alarm?['triggerTime'] as int?;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.alarm),
                  title: Text(
                    trigger == null
                        ? 'No upcoming alarm'
                        : DateFormat('EEE, MMM d • h:mm a').format(
                            DateTime.fromMillisecondsSinceEpoch(trigger)),
                  ),
                  subtitle: const Text('Next system alarm'),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _refresh,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.alarm_on_outlined,
            title: 'Open alarms',
            onTap: LauncherService.openAlarmApp,
          ),
          _ActionTile(
            icon: Icons.add_alarm_outlined,
            title: 'Create alarm',
            onTap: LauncherService.createAlarm,
          ),
          _ActionTile(
            icon: Icons.timer_outlined,
            title: 'Timer',
            onTap: LauncherService.openTimer,
          ),
          _ActionTile(
            icon: Icons.av_timer_outlined,
            title: 'Stopwatch',
            onTap: LauncherService.openStopwatch,
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Future<bool> Function() onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.open_in_new),
      onTap: () async {
        final ok = await onTap();
        if (!context.mounted || ok) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $title')),
        );
      },
    );
  }
}
