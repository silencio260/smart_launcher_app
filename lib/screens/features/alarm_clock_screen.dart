import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/mini_app_repositories.dart';
import '../../services/launcher_service.dart';
import 'mini_app_chrome.dart';

class AlarmClockScreen extends StatefulWidget {
  const AlarmClockScreen({super.key});

  @override
  State<AlarmClockScreen> createState() => _AlarmClockScreenState();
}

class _AlarmClockScreenState extends State<AlarmClockScreen> {
  final _repo = ClockRepository();
  var _tab = 1;
  Timer? _ticker;
  Duration _stopwatch = Duration.zero;
  bool _running = false;
  DateTime? _lastTick;
  var _timerDuration = const Duration(minutes: 5);
  var _timerRemaining = const Duration(minutes: 5);
  bool _timerRunning = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    final now = DateTime.now();
    if (_running && _lastTick != null) {
      _stopwatch += now.difference(_lastTick!);
    }
    if (_timerRunning && _lastTick != null) {
      final next = _timerRemaining - now.difference(_lastTick!);
      _timerRemaining = next.isNegative ? Duration.zero : next;
      if (_timerRemaining == Duration.zero) _timerRunning = false;
    }
    _lastTick = now;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['World Clock', 'Alarms', 'Stopwatch', 'Timers'];
    return MiniAppScaffold(
      title: titles[_tab],
      actions: [
        if (_tab == 1)
          IconButton(
            icon: const Icon(Icons.add, color: miniAppAccent),
            onPressed: _addAlarm,
          ),
      ],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: miniAppBackground,
        selectedItemColor: miniAppAccent,
        unselectedItemColor: miniAppMuted,
        currentIndex: _tab,
        onTap: (index) => setState(() => _tab = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.public),
            label: 'World Clock',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.alarm),
            label: 'Alarms',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.timer_outlined),
            label: 'Stopwatch',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.timelapse),
            label: 'Timers',
          ),
        ],
      ),
      child: IndexedStack(
        index: _tab,
        children: [
          _WorldClockTab(repo: _repo),
          _AlarmsTab(repo: _repo, onChanged: () => setState(() {})),
          _buildStopwatch(),
          _buildTimers(),
        ],
      ),
    );
  }

  Widget _buildStopwatch() {
    final minutes =
        _stopwatch.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds =
        _stopwatch.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hundredths = (_stopwatch.inMilliseconds.remainder(1000) ~/ 10)
        .toString()
        .padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 42, 24, 0),
      child: Column(
        children: [
          Text(
            '${_stopwatch.inHours.toString().padLeft(2, '0')}:$minutes,$seconds',
            style: const TextStyle(fontSize: 74, fontWeight: FontWeight.w300),
          ),
          Text(hundredths, style: const TextStyle(color: miniAppMuted)),
          const SizedBox(height: 70),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _RoundClockButton(
                label: _running ? 'Lap' : 'Reset',
                color: miniAppSurface,
                onTap: () {
                  if (!_running) setState(() => _stopwatch = Duration.zero);
                },
              ),
              _RoundClockButton(
                label: _running ? 'Stop' : 'Start',
                color: _running
                    ? const Color(0xFF4A1E1E)
                    : const Color(0xFF0B3D1B),
                textColor: _running ? Colors.redAccent : Colors.greenAccent,
                onTap: () => setState(() {
                  _running = !_running;
                  _lastTick = DateTime.now();
                }),
              ),
            ],
          ),
          const SizedBox(height: 26),
          const Divider(color: miniAppSurface2),
        ],
      ),
    );
  }

  Widget _buildTimers() {
    final hours = _timerDuration.inHours;
    final minutes = _timerDuration.inMinutes.remainder(60);
    final seconds = _timerDuration.inSeconds.remainder(60);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 44, 24, 120),
      children: [
        CupertinoTheme(
          data: const CupertinoThemeData(brightness: Brightness.dark),
          child: SizedBox(
            height: 150,
            child: CupertinoTimerPicker(
              mode: CupertinoTimerPickerMode.hms,
              initialTimerDuration: _timerDuration,
              onTimerDurationChanged: (value) => setState(() {
                _timerDuration = value;
                if (!_timerRunning) _timerRemaining = value;
              }),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _RoundClockButton(
              label: 'Cancel',
              color: miniAppSurface,
              onTap: () => setState(() {
                _timerRunning = false;
                _timerRemaining = _timerDuration;
              }),
            ),
            _RoundClockButton(
              label: _timerRunning ? 'Pause' : 'Start',
              color: const Color(0xFF0B3D1B),
              textColor: Colors.greenAccent,
              onTap: () => setState(() {
                if (_timerDuration == Duration.zero) return;
                _timerRunning = !_timerRunning;
                _lastTick = DateTime.now();
              }),
            ),
          ],
        ),
        const SizedBox(height: 24),
        MiniCard(
          child: Column(
            children: [
              _SettingsRow('Label', 'Timer'),
              _SettingsRow('When Timer Ends', 'Default'),
              _SettingsRow(
                'Remaining',
                '${_timerRemaining.inHours.toString().padLeft(2, '0')}:'
                    '${_timerRemaining.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
                    '${_timerRemaining.inSeconds.remainder(60).toString().padLeft(2, '0')}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final preset in _repo.timerPresets())
              ActionChip(
                backgroundColor: miniAppSurface,
                label: Text(preset['label'].toString()),
                onPressed: () => setState(() {
                  final seconds = preset['seconds'] as int? ?? 60;
                  _timerDuration = Duration(seconds: seconds);
                  _timerRemaining = _timerDuration;
                }),
              ),
          ],
        ),
        Offstage(
          child: Text('$hours$minutes$seconds'),
        ),
      ],
    );
  }

  Future<void> _addAlarm() async {
    var selected = TimeOfDay.now();
    final label = TextEditingController(text: 'Alarm');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: miniAppSurface,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 180,
                  child: CupertinoTheme(
                    data: const CupertinoThemeData(brightness: Brightness.dark),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.time,
                      initialDateTime:
                          DateTime(2024, 1, 1, selected.hour, selected.minute),
                      onDateTimeChanged: (value) =>
                          selected = TimeOfDay.fromDateTime(value),
                    ),
                  ),
                ),
                TextField(
                  controller: label,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save Alarm'),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final alarm = await _repo.addAlarm(
      hour: selected.hour,
      minute: selected.minute,
      label: label.text.trim().isEmpty ? 'Alarm' : label.text.trim(),
    );
    await _schedule(alarm);
    setState(() {});
  }

  Future<void> _schedule(ClockAlarmRecord alarm) async {
    final now = DateTime.now();
    var trigger =
        DateTime(now.year, now.month, now.day, alarm.hour, alarm.minute);
    if (!trigger.isAfter(now)) trigger = trigger.add(const Duration(days: 1));
    if (!await LauncherService.canScheduleExactAlarms()) {
      await LauncherService.requestExactAlarmAccess();
      return;
    }
    await LauncherService.scheduleSmartAlarm(
      id: alarm.id,
      triggerAtMillis: trigger.millisecondsSinceEpoch,
      label: alarm.label,
    );
  }
}

class _WorldClockTab extends StatelessWidget {
  final ClockRepository repo;

  const _WorldClockTab({required this.repo});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 120),
      itemCount: repo.worldCities().length,
      separatorBuilder: (_, __) => const Divider(color: miniAppSurface),
      itemBuilder: (context, index) {
        final city = repo.worldCities()[index];
        final offset = city['offset'] as int? ?? 0;
        final local = now.add(Duration(hours: offset));
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Today, ${offset >= 0 ? '+' : ''}${offset}HRS',
                      style: const TextStyle(color: miniAppMuted)),
                  const SizedBox(height: 8),
                  Text(city['city'].toString(),
                      style: const TextStyle(fontSize: 30)),
                ],
              ),
            ),
            Text(DateFormat.Hm().format(local),
                style:
                    const TextStyle(fontSize: 54, fontWeight: FontWeight.w300)),
          ],
        );
      },
    );
  }
}

class _AlarmsTab extends StatelessWidget {
  final ClockRepository repo;
  final VoidCallback onChanged;

  const _AlarmsTab({required this.repo, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final alarms = repo.alarms();
    if (alarms.isEmpty) {
      return const EmptyMiniState(
        icon: Icons.alarm_add_outlined,
        title: 'No alarms yet',
        subtitle: 'Tap + to create a proper launcher alarm.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
      itemCount: alarms.length + 1,
      separatorBuilder: (_, __) => const Divider(color: miniAppSurface2),
      itemBuilder: (context, index) {
        if (index == 0) {
          return MiniCard(
            child: Row(
              children: [
                const Icon(Icons.info, color: miniAppAccent),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Optimize Alarms',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: LauncherService.requestExactAlarmAccess,
                  child: const Text('Optimize'),
                ),
              ],
            ),
          );
        }
        final alarm = alarms[index - 1];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            alarm.timeLabel,
            style: TextStyle(
              fontSize: 58,
              fontWeight: FontWeight.w300,
              color: alarm.enabled ? Colors.white : miniAppMuted,
            ),
          ),
          subtitle:
              Text(alarm.label, style: const TextStyle(color: miniAppMuted)),
          trailing: Switch(
            value: alarm.enabled,
            onChanged: (value) async {
              await repo.saveAlarm(ClockAlarmRecord(
                id: alarm.id,
                hour: alarm.hour,
                minute: alarm.minute,
                label: alarm.label,
                enabled: value,
                repeatDays: alarm.repeatDays,
                vibrate: alarm.vibrate,
                snoozeMinutes: alarm.snoozeMinutes,
                createdAt: alarm.createdAt,
              ));
              if (!value) await LauncherService.cancelSmartAlarm(alarm.id);
              onChanged();
            },
          ),
        );
      },
    );
  }
}

class _RoundClockButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;

  const _RoundClockButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.textColor = miniAppMuted,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 108,
        height: 108,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text(label, style: TextStyle(color: textColor, fontSize: 20)),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final String value;

  const _SettingsRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: miniAppMuted, fontSize: 18),
            ),
          ),
          const Icon(Icons.chevron_right, color: miniAppMuted),
        ],
      ),
    );
  }
}
