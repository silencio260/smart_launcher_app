import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/mini_app_repositories.dart';
import '../../services/clock_service.dart';
import '../../services/launcher_service.dart';
import 'clock/alarm_edit_screen.dart';
import 'clock/clock_theme.dart';
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
    final titles = ['Alarm', 'World clock', 'Stopwatch', 'Timer'];
    return MiniAppScaffold(
      title: titles[_tab],
      actions: [
        if (_tab == 0)
          IconButton(
            tooltip: 'Test alarm in 5s',
            icon: const Icon(Icons.play_circle_outline, color: clockAccent),
            onPressed: _testAlarm,
          ),
        if (_tab == 0)
          IconButton(
            icon: const Icon(Icons.add, color: clockAccent),
            onPressed: () => _openEditor(null),
          ),
        if (_tab == 1)
          IconButton(
            icon: const Icon(Icons.add_location_alt_outlined,
                color: clockAccent),
            onPressed: _addCity,
          ),
      ],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: miniAppBackground,
        selectedItemColor: Colors.white,
        unselectedItemColor: miniAppMuted,
        currentIndex: _tab,
        onTap: (index) => setState(() => _tab = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.alarm), label: 'Alarm'),
          BottomNavigationBarItem(
              icon: Icon(Icons.language), label: 'World clock'),
          BottomNavigationBarItem(
              icon: Icon(Icons.timer_outlined), label: 'Stopwatch'),
          BottomNavigationBarItem(
              icon: Icon(Icons.hourglass_bottom), label: 'Timer'),
        ],
      ),
      child: Theme(
        data: clockThemeOf(context),
        child: IndexedStack(
          index: _tab,
          children: [
            _buildAlarms(),
            _buildWorldClock(),
            _buildStopwatch(),
            _buildTimer(),
          ],
        ),
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
    final enabled = alarm.enabled;
    final timeColor = enabled ? Colors.white : miniAppMuted;
    final showLabel =
        alarm.label.trim().isNotEmpty && alarm.label.trim() != 'Alarm';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Dismissible(
        key: ValueKey(alarm.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: Colors.red.shade900,
            borderRadius: BorderRadius.circular(20),
          ),
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
        child: ClockCard(
          onTap: () => _openEditor(alarm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClockTime(
                      hour: alarm.hour,
                      minute: alarm.minute,
                      color: timeColor,
                    ),
                    if (showLabel) ...[
                      const SizedBox(height: 2),
                      Text(
                        alarm.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: miniAppMuted, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _alarmSchedule(alarm, enabled),
              const SizedBox(width: 12),
              Switch(
                value: enabled,
                onChanged: (value) => _toggleAlarm(alarm, value),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Right-side schedule indicator: a `M T W T F S S` strip for custom repeats,
  /// or a text label ("Every day" / the next date) otherwise — One UI style.
  Widget _alarmSchedule(ClockAlarmRecord alarm, bool enabled) {
    final days = alarm.repeatDays.toSet();
    if (days.isNotEmpty && days.length != 7) {
      return RepeatDaysStrip(
        days: days,
        activeColor: enabled ? Colors.white : miniAppMuted,
        inactiveColor: miniAppMuted,
      );
    }
    final label = days.length == 7
        ? 'Every day'
        : DateFormat('EEE, d MMM').format(_clock.nextRing(alarm));
    return Text(
      label,
      style: TextStyle(
        color: enabled ? Colors.white70 : miniAppMuted,
        fontSize: 14,
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
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
      children: [
        Center(
          child: ClockTime(
            hour: now.hour,
            minute: now.minute,
            fontSize: 64,
            weight: FontWeight.w200,
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('${DateFormat('EEEE, d MMM').format(now)} · $localName',
              style: const TextStyle(color: miniAppMuted, fontSize: 15)),
        ),
        const SizedBox(height: 24),
        for (final city in cities) _cityRow(city),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _addCity,
          icon: const Icon(Icons.add, color: clockAccent),
          label: const Text('Add city', style: TextStyle(color: Colors.white)),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Dismissible(
        key: ValueKey('city_$zoneId'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: Colors.red.shade900,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        onDismissed: (_) async {
          await _clock.removeCity(zoneId);
          if (mounted) setState(() {});
        },
        child: ClockCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(ClockService.offsetLabel(offsetMin),
                        style:
                            const TextStyle(color: miniAppMuted, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ClockTime(
                hour: time.hour,
                minute: time.minute,
                fontSize: 40,
                weight: FontWeight.w300,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Stopwatch -----------------------------------------------------------

  Widget _buildStopwatch() {
    final state = _stopRepo.state();
    final elapsed = state.elapsedMs();
    final laps = state.laps;
    final running = state.running;
    final hasElapsed = elapsed > 0;
    // Live time of the lap in progress (since the last recorded lap).
    final currentLap = elapsed - (laps.isEmpty ? 0 : laps.last);

    // Fastest / slowest lap, so they can be emphasised in black & white
    // (bold-white vs muted) the way One UI marks them with colour.
    int? fastest, slowest;
    if (laps.length >= 2) {
      var best = _lapSplit(0, laps), worst = best;
      fastest = slowest = 0;
      for (var i = 1; i < laps.length; i++) {
        final s = _lapSplit(i, laps);
        if (s < best) {
          best = s;
          fastest = i;
        }
        if (s > worst) {
          worst = s;
          slowest = i;
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 42, 24, 120),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(_fmtClock(elapsed, withCentis: true),
                  style: const TextStyle(
                      fontSize: 96, fontWeight: FontWeight.w200)),
            ),
            if (laps.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_fmtClock(currentLap, withCentis: true),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: miniAppMuted, fontSize: 24)),
            ],
          ],
        ),
        const SizedBox(height: 40),
        Row(
          children: [
            Expanded(
              child: _ClockPillButton(
                label: running ? 'Lap' : (hasElapsed ? 'Reset' : 'Lap'),
                color: miniAppSurface,
                textColor: Colors.white,
                onTap: hasElapsed
                    ? () async {
                        if (running) {
                          await _stopRepo.lap();
                        } else {
                          await _stopRepo.reset();
                        }
                        if (mounted) setState(() {});
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _ClockPillButton(
                label: running ? 'Stop' : (hasElapsed ? 'Resume' : 'Start'),
                color: Colors.white,
                textColor: Colors.black,
                onTap: () async {
                  if (running) {
                    await _stopRepo.pause();
                  } else {
                    await _stopRepo.startOrResume();
                  }
                  if (mounted) setState(() {});
                },
              ),
            ),
          ],
        ),
        if (laps.isNotEmpty) ...[
          const SizedBox(height: 34),
          const _LapHeader(),
          const Divider(color: miniAppSurface2),
          for (var i = laps.length - 1; i >= 0; i--)
            _lapRow(i, laps, fastest: fastest, slowest: slowest),
        ],
      ],
    );
  }

  int _lapSplit(int index, List<int> laps) =>
      index == 0 ? laps[0] : laps[index] - laps[index - 1];

  Widget _lapRow(int index, List<int> laps, {int? fastest, int? slowest}) {
    final total = laps[index];
    final split = _lapSplit(index, laps);
    final color = index == slowest
        ? miniAppMuted
        : Colors.white;
    final weight =
        index == fastest ? FontWeight.w700 : FontWeight.w400;
    final style = TextStyle(color: color, fontWeight: weight, fontSize: 16);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text((index + 1).toString().padLeft(2, '0'), style: style),
          ),
          Expanded(
            flex: 3,
            child: Text(_fmtClock(split, withCentis: true),
                textAlign: TextAlign.center, style: style),
          ),
          Expanded(
            flex: 3,
            child: Text(_fmtClock(total, withCentis: true),
                textAlign: TextAlign.right, style: style),
          ),
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
    final presetSeconds = _pickerDuration.inSeconds;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
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
        const SizedBox(height: 16),
        TextField(
          controller: _timerLabel,
          cursorColor: Colors.white,
          decoration: const InputDecoration(
            labelText: 'Timer name',
            border: UnderlineInputBorder(),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final preset in _clock.timerPresets())
              _PresetCircle(
                name: preset['label'].toString(),
                seconds: preset['seconds'] as int? ?? 60,
                selected: (preset['seconds'] as int? ?? 60) == presetSeconds,
                fmtDuration: _fmtDurationLabel,
                onTap: () => setState(() => _pickerDuration =
                    Duration(seconds: preset['seconds'] as int? ?? 60)),
              ),
          ],
        ),
        const SizedBox(height: 32),
        Center(
          child: SizedBox(
            width: 200,
            child: _ClockPillButton(
              label: 'Start',
              color: Colors.white,
              textColor: Colors.black,
              onTap: _pickerDuration.inSeconds <= 0
                  ? null
                  : () async {
                      if (!await LauncherService.canScheduleExactAlarms()) {
                        await LauncherService.requestExactAlarmAccess();
                      }
                      await _timerRepo.start(_pickerDuration, _timerLabel.text);
                      if (mounted) setState(() {});
                    },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimerRunning(CountdownTimerState state) {
    final remaining = state.remainingSeconds();
    final done = remaining <= 0;
    final pausedProgress = state.durationSeconds <= 0
        ? 0.0
        : (remaining / state.durationSeconds).clamp(0.0, 1.0);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 120),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AspectRatio(
              aspectRatio: 1,
              child: _TimerRing(
                running: state.running && !done,
                endsAtEpochMs: state.endsAtEpochMs,
                totalSeconds: state.durationSeconds,
                pausedProgress: done ? 0 : pausedProgress,
                color: state.running ? Colors.white : miniAppMuted,
                child: Padding(
                  padding: const EdgeInsets.all(44),
                  child: done
                      ? const Text("Time's up",
                          style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w300,
                              color: Colors.white))
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_fmtDurationLabel(state.durationSeconds),
                                  style: const TextStyle(
                                      color: miniAppMuted, fontSize: 18)),
                              const SizedBox(height: 10),
                              Text(_fmtTimerBig(remaining),
                                  style: const TextStyle(
                                      fontSize: 82,
                                      fontWeight: FontWeight.w200,
                                      color: Colors.white)),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.notifications_none,
                                      size: 16, color: miniAppMuted),
                                  const SizedBox(width: 5),
                                  Text(_fmtFinishClock(remaining),
                                      style: const TextStyle(
                                          color: miniAppMuted, fontSize: 15)),
                                ],
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 48),
        Row(
          children: [
            Expanded(
              child: _ClockPillButton(
                label: done ? 'Dismiss' : 'Delete',
                color: miniAppSurface,
                textColor: Colors.white,
                onTap: () async {
                  await _timerRepo.cancel();
                  if (mounted) setState(() {});
                },
              ),
            ),
            if (!done) ...[
              const SizedBox(width: 16),
              Expanded(
                child: _ClockPillButton(
                  label: state.running ? 'Pause' : 'Resume',
                  color: Colors.white,
                  textColor: Colors.black,
                  onTap: () async {
                    if (state.running) {
                      await _timerRepo.pause();
                    } else {
                      await _timerRepo.resume();
                    }
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ---- Formatting ----------------------------------------------------------

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

  /// Big countdown digits inside the ring: seconds-only under a minute, then
  /// `m:ss`, then `h:mm:ss` — One UI style (no leading zero on the lead unit).
  String _fmtTimerBig(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds ~/ 60) % 60;
    final s = totalSeconds % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    if (totalSeconds >= 60) return '$m:$ss';
    return '$s';
  }

  /// Friendly label of the originally-set duration ("1 m", "10 m", "1 h 5 m").
  String _fmtDurationLabel(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds ~/ 60) % 60;
    final s = totalSeconds % 60;
    final parts = <String>[
      if (h > 0) '$h h',
      if (m > 0) '$m m',
      if (s > 0 || (h == 0 && m == 0)) '$s s',
    ];
    return parts.join(' ');
  }

  /// Wall-clock time the timer will finish at (honours the 24-hour setting).
  String _fmtFinishClock(int remainingSeconds) {
    final end = DateTime.now().add(Duration(seconds: remainingSeconds));
    final use24h = MediaQuery.of(context).alwaysUse24HourFormat;
    final text = DateFormat(use24h ? 'HH:mm' : 'h:mm a').format(end);
    return use24h ? text : text.toLowerCase();
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
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.shield_outlined, color: Colors.white),
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
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
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

/// One UI-style stadium (pill) action button. A null [onTap] renders a
/// disabled, muted pill (e.g. "Lap" before the stopwatch is started).
class _ClockPillButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback? onTap;

  const _ClockPillButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.textColor = miniAppMuted,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? color : miniAppSurface,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: enabled ? textColor : miniAppMuted,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Column header for the stopwatch lap table.
class _LapHeader extends StatelessWidget {
  const _LapHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: miniAppMuted, fontSize: 14);
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('Lap', style: style)),
          Expanded(
              flex: 3,
              child: Text('Lap times',
                  textAlign: TextAlign.center, style: style)),
          Expanded(
              flex: 3,
              child: Text('Overall time',
                  textAlign: TextAlign.right, style: style)),
        ],
      ),
    );
  }
}

/// Circular timer preset (e.g. "Focus" / 25 m). Selected → white ring; else a
/// flat surface circle.
class _PresetCircle extends StatelessWidget {
  final String name;
  final int seconds;
  final bool selected;
  final String Function(int) fmtDuration;
  final VoidCallback onTap;

  const _PresetCircle({
    required this.name,
    required this.seconds,
    required this.selected,
    required this.fmtDuration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 96,
        height: 96,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? Colors.transparent : miniAppSurface,
          border: Border.all(
            color: selected ? Colors.white : miniAppSurface2,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(fmtDuration(seconds),
                style: const TextStyle(color: miniAppMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// Circular countdown ring with a centred [child]. While [running] it repaints
/// every frame, sweeping the arc smoothly from the wall clock (rather than
/// stepping once per state tick); when paused it shows [pausedProgress].
class _TimerRing extends StatefulWidget {
  final bool running;
  final int? endsAtEpochMs;
  final int totalSeconds;
  final double pausedProgress;
  final Color color;
  final Widget child;

  const _TimerRing({
    required this.running,
    required this.endsAtEpochMs,
    required this.totalSeconds,
    required this.pausedProgress,
    required this.color,
    required this.child,
  });

  @override
  State<_TimerRing> createState() => _TimerRingState();
}

class _TimerRingState extends State<_TimerRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _frames =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_TimerRing old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  /// Run the per-frame ticker only while counting down, to avoid burning frames
  /// when paused.
  void _syncTicker() {
    if (widget.running) {
      if (!_frames.isAnimating) _frames.repeat();
    } else if (_frames.isAnimating) {
      _frames.stop();
    }
  }

  double _liveProgress() {
    if (widget.running &&
        widget.endsAtEpochMs != null &&
        widget.totalSeconds > 0) {
      final msLeft =
          widget.endsAtEpochMs! - DateTime.now().millisecondsSinceEpoch;
      return (msLeft / 1000 / widget.totalSeconds).clamp(0.0, 1.0);
    }
    return widget.pausedProgress.clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _frames,
      child: Center(child: widget.child),
      builder: (context, child) => CustomPaint(
        painter: _RingPainter(progress: _liveProgress(), color: widget.color),
        child: child,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = miniAppSurface2;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);

    if (progress > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(
          rect, -math.pi / 2, 2 * math.pi * progress, false, arc);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
