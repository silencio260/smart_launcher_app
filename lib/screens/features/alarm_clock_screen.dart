import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/mini_app_repositories.dart';
import '../../services/clock_service.dart';
import '../../services/launcher_service.dart';
import 'clock/alarm_edit_screen.dart';
import 'clock/world_clock_picker_screen.dart';
import 'mini_app_chrome.dart';

class AlarmClockScreen extends StatefulWidget {
  const AlarmClockScreen({super.key});

  @override
  State<AlarmClockScreen> createState() => _AlarmClockScreenState();
}

class _AlarmClockScreenState extends State<AlarmClockScreen>
    with WidgetsBindingObserver {
  final _clock = ClockRepository();
  final _timerRepo = TimerRepository();
  final _stopRepo = StopwatchRepository();

  var _tab = 0;
  Timer? _ticker;

  // Timer picker state (the not-yet-started duration + label).
  Duration _pickerDuration = const Duration(minutes: 5);
  final _timerLabel = TextEditingController(text: 'Timer');

  // Permission setup state.
  bool _exactAlarm = true;
  bool _notifications = true;
  bool _fullScreen = true;
  bool _battery = true;

  // Only auto-prompt for notifications once per app session.
  static bool _notificationPromptShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pickerDuration =
        Duration(seconds: _timerRepo.state().durationSeconds);
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
    _clock.syncFiredAlarms().then((_) {
      if (mounted) setState(() {});
    });
    _loadPermissions();
    _maybePromptNotifications();
  }

  /// Notifications gate the entire ring UI on Android 13+, so ask up front the
  /// first time the clock is opened rather than waiting for the user to notice
  /// the setup banner.
  Future<void> _maybePromptNotifications() async {
    if (_notificationPromptShown) return;
    _notificationPromptShown = true;
    final status = await Permission.notification.status;
    if (!status.isGranted && !status.isPermanentlyDenied) {
      await Permission.notification.request();
      await _loadPermissions();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _timerLabel.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPermissions();
      _clock.syncFiredAlarms().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _loadPermissions() async {
    final exact = await LauncherService.canScheduleExactAlarms();
    final fullScreen = await LauncherService.canUseFullScreenIntent();
    final battery = await LauncherService.isIgnoringBatteryOptimizations();
    final notifications = await Permission.notification.isGranted;
    if (!mounted) return;
    setState(() {
      _exactAlarm = exact;
      _fullScreen = fullScreen;
      _battery = battery;
      _notifications = notifications;
    });
  }

  bool get _needsSetup =>
      !_exactAlarm || !_notifications || !_fullScreen || !_battery;

  @override
  Widget build(BuildContext context) {
    final titles = ['Alarms', 'World Clock', 'Stopwatch', 'Timers'];
    return MiniAppScaffold(
      title: titles[_tab],
      actions: [
        if (_tab == 0)
          IconButton(
            tooltip: 'Test alarm in 5s',
            icon: const Icon(Icons.play_circle_outline, color: miniAppAccent),
            onPressed: _testAlarm,
          ),
        if (_tab == 0)
          IconButton(
            icon: const Icon(Icons.add, color: miniAppAccent),
            onPressed: () => _openEditor(null),
          ),
        if (_tab == 1)
          IconButton(
            icon: const Icon(Icons.add_location_alt_outlined,
                color: miniAppAccent),
            onPressed: _addCity,
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
          BottomNavigationBarItem(icon: Icon(Icons.alarm), label: 'Alarms'),
          BottomNavigationBarItem(icon: Icon(Icons.public), label: 'World'),
          BottomNavigationBarItem(
              icon: Icon(Icons.timer_outlined), label: 'Stopwatch'),
          BottomNavigationBarItem(
              icon: Icon(Icons.hourglass_bottom), label: 'Timer'),
        ],
      ),
      child: IndexedStack(
        index: _tab,
        children: [
          _buildAlarms(),
          _buildWorldClock(),
          _buildStopwatch(),
          _buildTimer(),
        ],
      ),
    );
  }

  // ---- Alarms --------------------------------------------------------------

  Future<void> _openEditor(ClockAlarmRecord? existing) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AlarmEditScreen(repo: _clock, existing: existing),
      ),
    );
    if (changed == true) {
      await _loadPermissions();
      if (mounted) setState(() {});
    }
  }

  Future<void> _toggleAlarm(ClockAlarmRecord alarm, bool value) async {
    await _clock.saveAndSchedule(alarm.copyWith(enabled: value));
    if (mounted) setState(() {});
  }

  /// Fires a throwaway alarm ~5s out through the real native path so the user
  /// can verify the full notification → full-screen → Snooze/Dismiss flow (and
  /// be prompted for any missing permission) without scheduling and waiting.
  Future<void> _testAlarm() async {
    if (!await LauncherService.canScheduleExactAlarms()) {
      await LauncherService.requestExactAlarmAccess();
    }
    final notif = await Permission.notification.status;
    if (!notif.isGranted && !notif.isPermanentlyDenied) {
      await Permission.notification.request();
    }
    await _loadPermissions();
    final trigger = DateTime.now().add(const Duration(seconds: 5));
    final ok = await LauncherService.scheduleSmartAlarm(
      id: ClockRepository.testAlarmId,
      triggerAtMillis: trigger.millisecondsSinceEpoch,
      label: 'Test alarm',
      hour: trigger.hour,
      minute: trigger.minute,
      vibrate: true,
      autoSilenceMinutes: 1,
      kind: 'alarm',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Test alarm rings in 5s — lock the phone to see the full-screen ring.'
            : 'Could not schedule. Allow exact alarms, then try again.'),
      ),
    );
  }

  Widget _buildAlarms() {
    final alarms = _clock.alarms();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
      children: [
        if (_needsSetup) ...[
          _SetupCard(
            exactAlarm: _exactAlarm,
            notifications: _notifications,
            fullScreen: _fullScreen,
            battery: _battery,
            onFixExact: () async {
              await LauncherService.requestExactAlarmAccess();
            },
            onFixNotifications: () async {
              await Permission.notification.request();
              await _loadPermissions();
            },
            onFixFullScreen: () async {
              await LauncherService.requestFullScreenIntentAccess();
            },
            onFixBattery: () async {
              await LauncherService.requestIgnoreBatteryOptimizations();
            },
          ),
          const SizedBox(height: 18),
        ],
        if (alarms.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 60),
            child: EmptyMiniState(
              icon: Icons.alarm_add_outlined,
              title: 'No alarms yet',
              subtitle: 'Tap + to create a reliable launcher alarm.',
            ),
          )
        else
          for (final alarm in alarms) _alarmTile(alarm),
      ],
    );
  }

  Widget _alarmTile(ClockAlarmRecord alarm) {
    final color = alarm.enabled ? Colors.white : miniAppMuted;
    final repeat = ClockService.repeatLabel(alarm.repeatDays);
    final subtitle = alarm.enabled
        ? '$repeat · ${ClockService.humanizeUntil(_clock.nextRing(alarm))}'
        : repeat;
    return Dismissible(
      key: ValueKey(alarm.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.red.shade900,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
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
            ) ??
            false;
      },
      onDismissed: (_) async {
        await _clock.deleteAlarm(alarm.id);
        if (mounted) setState(() {});
      },
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: () => _openEditor(alarm),
        title: Text(
          alarm.timeLabel,
          style: TextStyle(
              fontSize: 52, fontWeight: FontWeight.w300, color: color),
        ),
        subtitle: Text(
          '${alarm.label} · $subtitle',
          style: const TextStyle(color: miniAppMuted),
        ),
        trailing: Switch(
          value: alarm.enabled,
          onChanged: (value) => _toggleAlarm(alarm, value),
        ),
      ),
    );
  }

  // ---- World clock ---------------------------------------------------------

  Future<void> _addCity() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => WorldClockPickerScreen(repo: _clock),
      ),
    );
    if (added == true && mounted) setState(() {});
  }

  Widget _buildWorldClock() {
    final now = DateTime.now();
    final localName = _localCityName();
    final cities = _clock.worldCities();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
      children: [
        Text(DateFormat.Hm().format(now),
            style:
                const TextStyle(fontSize: 72, fontWeight: FontWeight.w200)),
        Text('${DateFormat('EEEE, d MMM').format(now)} · $localName',
            style: const TextStyle(color: miniAppMuted, fontSize: 15)),
        const SizedBox(height: 8),
        const Divider(color: miniAppSurface2),
        for (final city in cities) _cityRow(city),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _addCity,
          icon: const Icon(Icons.add, color: miniAppAccent),
          label: const Text('Add city'),
        ),
      ],
    );
  }

  String _localCityName() {
    final id = ClockService.localLocation.name;
    final part = id.contains('/') ? id.split('/').last : id;
    return part.replaceAll('_', ' ');
  }

  Widget _cityRow(Map<String, Object?> city) {
    final zoneId = city['zoneId']?.toString() ?? 'UTC';
    final name = city['name']?.toString() ?? zoneId;
    final time = ClockService.nowIn(zoneId);
    final offsetMin = ClockService.offsetMinutesFromLocal(zoneId);
    return Dismissible(
      key: ValueKey('city_$zoneId'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.red.shade900,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) async {
        await _clock.removeCity(zoneId);
        if (mounted) setState(() {});
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(
              ClockService.isDayTime(time)
                  ? Icons.wb_sunny_outlined
                  : Icons.nightlight_outlined,
              color: miniAppMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ClockService.offsetLabel(offsetMin),
                      style:
                          const TextStyle(color: miniAppMuted, fontSize: 13)),
                  Text(name, style: const TextStyle(fontSize: 26)),
                ],
              ),
            ),
            Text(DateFormat.Hm().format(time),
                style:
                    const TextStyle(fontSize: 44, fontWeight: FontWeight.w200)),
          ],
        ),
      ),
    );
  }

  // ---- Stopwatch -----------------------------------------------------------

  Widget _buildStopwatch() {
    final state = _stopRepo.state();
    final elapsed = state.elapsedMs();
    final laps = state.laps;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 42, 24, 120),
      children: [
        Center(
          child: Column(
            children: [
              Text(_fmtStopwatchMain(elapsed),
                  style: const TextStyle(
                      fontSize: 70, fontWeight: FontWeight.w200)),
              Text(_fmtStopwatchCentis(elapsed),
                  style: const TextStyle(color: miniAppMuted, fontSize: 18)),
            ],
          ),
        ),
        const SizedBox(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _RoundClockButton(
              label: state.running ? 'Lap' : 'Reset',
              color: miniAppSurface,
              onTap: () async {
                if (state.running) {
                  await _stopRepo.lap();
                } else {
                  await _stopRepo.reset();
                }
                if (mounted) setState(() {});
              },
            ),
            _RoundClockButton(
              label: state.running ? 'Stop' : 'Start',
              color: state.running
                  ? const Color(0xFF4A1E1E)
                  : const Color(0xFF0B3D1B),
              textColor:
                  state.running ? Colors.redAccent : Colors.greenAccent,
              onTap: () async {
                if (state.running) {
                  await _stopRepo.pause();
                } else {
                  await _stopRepo.startOrResume();
                }
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: 26),
        const Divider(color: miniAppSurface2),
        for (var i = laps.length - 1; i >= 0; i--) _lapRow(i, laps),
      ],
    );
  }

  Widget _lapRow(int index, List<int> laps) {
    final total = laps[index];
    final split = index == 0 ? total : total - laps[index - 1];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text('Lap ${index + 1}',
              style: const TextStyle(color: miniAppMuted)),
          const Spacer(),
          Text(_fmtClock(split, withCentis: true)),
          const SizedBox(width: 18),
          Text(_fmtClock(total, withCentis: true),
              style: const TextStyle(color: miniAppMuted)),
        ],
      ),
    );
  }

  // ---- Timer ---------------------------------------------------------------

  Widget _buildTimer() {
    final state = _timerRepo.state();
    if (state.isActive) {
      return _buildTimerRunning(state);
    }
    return _buildTimerSetup();
  }

  Widget _buildTimerSetup() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 120),
      children: [
        SizedBox(
          height: 180,
          child: CupertinoTheme(
            data: const CupertinoThemeData(brightness: Brightness.dark),
            child: CupertinoTimerPicker(
              mode: CupertinoTimerPickerMode.hms,
              initialTimerDuration: _pickerDuration,
              onTimerDurationChanged: (value) =>
                  setState(() => _pickerDuration = value),
            ),
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _timerLabel,
          decoration: const InputDecoration(
            labelText: 'Label',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: _RoundClockButton(
            label: 'Start',
            color: const Color(0xFF0B3D1B),
            textColor: Colors.greenAccent,
            onTap: () async {
              if (_pickerDuration.inSeconds <= 0) return;
              if (!await LauncherService.canScheduleExactAlarms()) {
                await LauncherService.requestExactAlarmAccess();
              }
              await _timerRepo.start(_pickerDuration, _timerLabel.text);
              if (mounted) setState(() {});
            },
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final preset in _clock.timerPresets())
              ActionChip(
                backgroundColor: miniAppSurface,
                label: Text(preset['label'].toString()),
                onPressed: () => setState(() {
                  final seconds = preset['seconds'] as int? ?? 60;
                  _pickerDuration = Duration(seconds: seconds);
                }),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimerRunning(CountdownTimerState state) {
    final remaining = state.remainingSeconds();
    final done = remaining <= 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 120),
      children: [
        Center(
          child: Text(state.label,
              style: const TextStyle(color: miniAppMuted, fontSize: 18)),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            done ? "Time's up" : _fmtTimer(remaining),
            style: TextStyle(
              fontSize: done ? 44 : 76,
              fontWeight: FontWeight.w200,
              color: done ? miniAppAccent : Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 50),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _RoundClockButton(
              label: done ? 'Done' : 'Cancel',
              color: miniAppSurface,
              onTap: () async {
                await _timerRepo.cancel();
                if (mounted) setState(() {});
              },
            ),
            if (!done)
              _RoundClockButton(
                label: state.running ? 'Pause' : 'Resume',
                color: const Color(0xFF0B3D1B),
                textColor: Colors.greenAccent,
                onTap: () async {
                  if (state.running) {
                    await _timerRepo.pause();
                  } else {
                    await _timerRepo.resume();
                  }
                  if (mounted) setState(() {});
                },
              ),
          ],
        ),
      ],
    );
  }

  // ---- Formatting ----------------------------------------------------------

  String _fmtStopwatchMain(int ms) {
    final h = ms ~/ 3600000;
    final m = (ms ~/ 60000) % 60;
    final s = (ms ~/ 1000) % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$mm:$ss' : '$mm:$ss';
  }

  String _fmtStopwatchCentis(int ms) =>
      ((ms ~/ 10) % 100).toString().padLeft(2, '0');

  String _fmtClock(int ms, {bool withCentis = false}) {
    final h = ms ~/ 3600000;
    final m = (ms ~/ 60000) % 60;
    final s = (ms ~/ 1000) % 60;
    final cs = (ms ~/ 10) % 100;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    final base = h > 0 ? '${h.toString().padLeft(2, '0')}:$mm:$ss' : '$mm:$ss';
    return withCentis ? '$base.${cs.toString().padLeft(2, '0')}' : base;
  }

  String _fmtTimer(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds ~/ 60) % 60;
    final s = totalSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

// ---- Setup card ------------------------------------------------------------

class _SetupCard extends StatelessWidget {
  final bool exactAlarm;
  final bool notifications;
  final bool fullScreen;
  final bool battery;
  final VoidCallback onFixExact;
  final VoidCallback onFixNotifications;
  final VoidCallback onFixFullScreen;
  final VoidCallback onFixBattery;

  const _SetupCard({
    required this.exactAlarm,
    required this.notifications,
    required this.fullScreen,
    required this.battery,
    required this.onFixExact,
    required this.onFixNotifications,
    required this.onFixFullScreen,
    required this.onFixBattery,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: miniAppSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: miniAppAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.shield_outlined, color: miniAppAccent),
              SizedBox(width: 10),
              Expanded(
                child: Text('Make alarms reliable',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Grant these so alarms ring on time, over the lockscreen, even '
            'after a reboot.',
            style: TextStyle(color: miniAppMuted, height: 1.3),
          ),
          if (!notifications) ...[
            const SizedBox(height: 12),
            _NotificationBanner(onAllow: onFixNotifications),
          ],
          const SizedBox(height: 8),
          if (!exactAlarm)
            _SetupRow('Exact alarms', 'Fix', onFixExact),
          if (!fullScreen)
            _SetupRow('Full-screen alarms', 'Allow', onFixFullScreen),
          if (!battery)
            _SetupRow('Ignore battery saver', 'Open', onFixBattery),
        ],
      ),
    );
  }
}

class _SetupRow extends StatelessWidget {
  final String label;
  final String action;
  final VoidCallback onTap;

  const _SetupRow(this.label, this.action, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline, color: miniAppAccent, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    );
  }
}

/// Prominent, can't-miss warning shown when notifications are denied — without
/// this permission the alarm rings with no notification and no full-screen UI,
/// so it gets a banner rather than a quiet pill.
class _NotificationBanner extends StatelessWidget {
  final VoidCallback onAllow;

  const _NotificationBanner({required this.onAllow});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF4A1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_off_outlined,
              color: Colors.redAccent),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "Alarms can't alert you until notifications are allowed.",
              style: TextStyle(
                  color: Colors.white,
                  height: 1.3,
                  fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: onAllow,
            child: const Text('Allow'),
          ),
        ],
      ),
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
