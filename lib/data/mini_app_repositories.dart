import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../services/clock_service.dart';
import '../services/launcher_service.dart';
import 'feature_hive_store.dart';
import 'world_cities.dart';

/// Stable native-alarm id for the single countdown timer.
const kLauncherTimerId = 'launcher_timer';

const _uuid = Uuid();

class ClockAlarmRecord {
  final String id;
  final int hour;
  final int minute;
  final String label;
  final bool enabled;

  /// Weekdays the alarm repeats on, 1 = Mon … 7 = Sun (empty = one-shot).
  final List<int> repeatDays;
  final bool vibrate;
  final int snoozeMinutes;

  /// Ringtone source: a `content://` / `file://` / `android.resource://` URI,
  /// or null for the device default alarm sound.
  final String? ringtoneUri;
  final String ringtoneTitle;
  final bool graduallyIncreaseVolume;

  /// Minutes before the alarm silences itself if untouched (0 = never).
  final int autoSilenceMinutes;
  final int createdAt;

  const ClockAlarmRecord({
    required this.id,
    required this.hour,
    required this.minute,
    required this.label,
    required this.enabled,
    required this.repeatDays,
    required this.vibrate,
    required this.snoozeMinutes,
    required this.createdAt,
    this.ringtoneUri,
    this.ringtoneTitle = 'Default',
    this.graduallyIncreaseVolume = false,
    this.autoSilenceMinutes = 10,
  });

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  ClockAlarmRecord copyWith({
    int? hour,
    int? minute,
    String? label,
    bool? enabled,
    List<int>? repeatDays,
    bool? vibrate,
    int? snoozeMinutes,
    Object? ringtoneUri = _unset,
    String? ringtoneTitle,
    bool? graduallyIncreaseVolume,
    int? autoSilenceMinutes,
  }) =>
      ClockAlarmRecord(
        id: id,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        label: label ?? this.label,
        enabled: enabled ?? this.enabled,
        repeatDays: repeatDays ?? this.repeatDays,
        vibrate: vibrate ?? this.vibrate,
        snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
        ringtoneUri:
            ringtoneUri == _unset ? this.ringtoneUri : ringtoneUri as String?,
        ringtoneTitle: ringtoneTitle ?? this.ringtoneTitle,
        graduallyIncreaseVolume:
            graduallyIncreaseVolume ?? this.graduallyIncreaseVolume,
        autoSilenceMinutes: autoSilenceMinutes ?? this.autoSilenceMinutes,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'schema': 2,
        'id': id,
        'hour': hour,
        'minute': minute,
        'label': label,
        'enabled': enabled,
        'repeatDays': repeatDays,
        'vibrate': vibrate,
        'snoozeMinutes': snoozeMinutes,
        'ringtoneUri': ringtoneUri,
        'ringtoneTitle': ringtoneTitle,
        'graduallyIncreaseVolume': graduallyIncreaseVolume,
        'autoSilenceMinutes': autoSilenceMinutes,
        'createdAt': createdAt,
      };

  static ClockAlarmRecord fromMap(Map map) => ClockAlarmRecord(
        id: map['id']?.toString() ?? _uuid.v4(),
        hour: map['hour'] as int? ?? 7,
        minute: map['minute'] as int? ?? 0,
        label: map['label']?.toString() ?? 'Alarm',
        enabled: map['enabled'] as bool? ?? true,
        repeatDays: (map['repeatDays'] as List?)?.cast<int>() ?? const [],
        vibrate: map['vibrate'] as bool? ?? true,
        snoozeMinutes: map['snoozeMinutes'] as int? ?? 5,
        ringtoneUri: (map['ringtoneUri'] as String?)?.trim().isEmpty ?? true
            ? null
            : map['ringtoneUri'] as String?,
        ringtoneTitle: map['ringtoneTitle']?.toString() ?? 'Default',
        graduallyIncreaseVolume:
            map['graduallyIncreaseVolume'] as bool? ?? false,
        autoSilenceMinutes: map['autoSilenceMinutes'] as int? ?? 10,
        createdAt:
            map['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      );
}

/// Sentinel so [ClockAlarmRecord.copyWith] can distinguish "leave ringtoneUri
/// unchanged" from "set ringtoneUri to null (use default sound)".
const Object _unset = Object();

class ClockRepository {
  Box get _alarms => FeatureHiveStore.box(FeatureHiveBoxes.clockAlarms);
  Box get _cities => FeatureHiveStore.box(FeatureHiveBoxes.clockWorldCities);
  Box get _timers => FeatureHiveStore.box(FeatureHiveBoxes.clockTimerPresets);

  List<ClockAlarmRecord> alarms() =>
      _alarms.values.whereType<Map>().map(ClockAlarmRecord.fromMap).toList()
        ..sort((a, b) => a.hour == b.hour
            ? a.minute.compareTo(b.minute)
            : a.hour.compareTo(b.hour));

  ClockAlarmRecord? alarm(String id) {
    final raw = _alarms.get(id);
    return raw is Map ? ClockAlarmRecord.fromMap(raw) : null;
  }

  /// Creates a new alarm (enabled, sensible defaults) and persists it. The
  /// caller is responsible for scheduling via [scheduleAlarm].
  Future<ClockAlarmRecord> addAlarm({
    required int hour,
    required int minute,
    String label = 'Alarm',
    List<int> repeatDays = const [],
  }) async {
    final alarm = ClockAlarmRecord(
      id: _uuid.v4(),
      hour: hour,
      minute: minute,
      label: label,
      enabled: true,
      repeatDays: repeatDays,
      vibrate: true,
      snoozeMinutes: 5,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _alarms.put(alarm.id, alarm.toMap());
    return alarm;
  }

  Future<void> saveAlarm(ClockAlarmRecord alarm) =>
      _alarms.put(alarm.id, alarm.toMap());

  Future<void> deleteAlarm(String id) async {
    await LauncherService.cancelSmartAlarm(id);
    await _alarms.delete(id);
  }

  /// Next moment [alarm] will ring (repeat-aware), for "next ring in …" labels.
  DateTime nextRing(ClockAlarmRecord alarm) => ClockService.nextTrigger(
        hour: alarm.hour,
        minute: alarm.minute,
        repeatDays: alarm.repeatDays,
      );

  /// Persists [alarm] and (re)schedules or cancels it natively to match its
  /// enabled state. Returns false if exact alarms aren't permitted yet.
  Future<bool> saveAndSchedule(ClockAlarmRecord alarm) async {
    await saveAlarm(alarm);
    if (!alarm.enabled) {
      await LauncherService.cancelSmartAlarm(alarm.id);
      return true;
    }
    return scheduleAlarm(alarm);
  }

  /// Schedules [alarm] with the native alarm manager using its full spec.
  Future<bool> scheduleAlarm(ClockAlarmRecord alarm) async {
    if (!await LauncherService.canScheduleExactAlarms()) return false;
    final trigger = nextRing(alarm);
    return LauncherService.scheduleSmartAlarm(
      id: alarm.id,
      triggerAtMillis: trigger.millisecondsSinceEpoch,
      label: alarm.label,
      hour: alarm.hour,
      minute: alarm.minute,
      repeatDays: alarm.repeatDays,
      ringtoneUri: alarm.ringtoneUri,
      ringtoneTitle: alarm.ringtoneTitle,
      vibrate: alarm.vibrate,
      graduallyIncreaseVolume: alarm.graduallyIncreaseVolume,
      autoSilenceMinutes: alarm.autoSilenceMinutes,
      snoozeMinutes: alarm.snoozeMinutes,
      kind: 'alarm',
    );
  }

  Future<void> rescheduleEnabledAlarms() async {
    try {
      await syncFiredAlarms();
      if (!await LauncherService.canScheduleExactAlarms()) return;
      for (final alarm in alarms().where((alarm) => alarm.enabled)) {
        await scheduleAlarm(alarm);
      }
    } catch (_) {}
  }

  /// Turns off one-shot alarms that already fired natively while the app was
  /// closed, so they don't reappear as enabled (and get re-armed for tomorrow).
  Future<void> syncFiredAlarms() async {
    try {
      final fired = await LauncherService.consumeFiredAlarms();
      for (final id in fired) {
        final existing = alarm(id);
        if (existing != null && existing.repeatDays.isEmpty && existing.enabled) {
          await saveAlarm(existing.copyWith(enabled: false));
        }
      }
    } catch (_) {}
  }

  // ---- World clock cities (IANA timezone backed) -------------------------

  /// Stored cities in display order. Migrates legacy `{city, offset}` entries
  /// to the IANA format on first read.
  List<Map<String, Object?>> worldCities() {
    final values = _cities.values.whereType<Map>().toList();
    final hasMigrated = values.any((e) => e['zoneId'] != null);
    if (!hasMigrated) {
      if (values.isNotEmpty) _cities.clear();
      _seedDefaultCities();
    }
    final result = _cities.values
        .whereType<Map>()
        .where((e) => e['zoneId'] != null)
        .map((e) => e.cast<String, Object?>())
        .toList();
    result.sort(
        (a, b) => (a['order'] as int? ?? 0).compareTo(b['order'] as int? ?? 0));
    return result;
  }

  void _seedDefaultCities() {
    const defaults = ['Europe/London', 'America/New_York', 'Asia/Tokyo'];
    var order = 0;
    for (final zoneId in defaults) {
      final city = worldCityFor(zoneId);
      if (city == null) continue;
      _cities.put(zoneId, {
        'schema': 1,
        'zoneId': zoneId,
        'name': city.name,
        'country': city.country,
        'order': order++,
      });
    }
  }

  bool hasCity(String zoneId) => _cities.containsKey(zoneId);

  Future<void> addCity(WorldCity city) async {
    if (_cities.containsKey(city.zoneId)) return;
    final maxOrder = _cities.values
        .whereType<Map>()
        .map((e) => e['order'] as int? ?? 0)
        .fold<int>(-1, (a, b) => a > b ? a : b);
    await _cities.put(city.zoneId, {
      'schema': 1,
      'zoneId': city.zoneId,
      'name': city.name,
      'country': city.country,
      'order': maxOrder + 1,
    });
  }

  Future<void> removeCity(String zoneId) => _cities.delete(zoneId);

  Future<void> reorderCities(List<String> orderedZoneIds) async {
    for (var i = 0; i < orderedZoneIds.length; i++) {
      final raw = _cities.get(orderedZoneIds[i]);
      if (raw is Map) {
        final updated = raw.cast<String, Object?>();
        updated['order'] = i;
        await _cities.put(orderedZoneIds[i], updated);
      }
    }
  }

  List<Map<String, Object?>> timerPresets() {
    if (_timers.isEmpty) {
      _timers.putAll({
        'focus': {'label': 'Focus', 'seconds': 1500},
        'powernap': {'label': 'Power nap', 'seconds': 1200},
        'tea': {'label': 'Tea', 'seconds': 180},
      });
    }
    return _timers.values
        .whereType<Map>()
        .map((e) => e.cast<String, Object?>())
        .toList(growable: false);
  }
}

/// Lookup a curated [WorldCity] by its IANA zone id (first match wins).
WorldCity? worldCityFor(String zoneId) {
  for (final c in worldCities) {
    if (c.zoneId == zoneId) return c;
  }
  return null;
}

// ---- Countdown timer ------------------------------------------------------

class CountdownTimerState {
  final int durationSeconds;

  /// Epoch millis when the timer will fire (only meaningful when [running]).
  final int? endsAtEpochMs;

  /// Seconds left when paused.
  final int pausedRemainingSeconds;
  final String label;
  final bool running;

  const CountdownTimerState({
    required this.durationSeconds,
    required this.endsAtEpochMs,
    required this.pausedRemainingSeconds,
    required this.label,
    required this.running,
  });

  static const idle = CountdownTimerState(
    durationSeconds: 300,
    endsAtEpochMs: null,
    pausedRemainingSeconds: 300,
    label: 'Timer',
    running: false,
  );

  bool get isActive => running || pausedRemainingSeconds != durationSeconds;

  /// Live seconds remaining, computed from the wall clock when running.
  int remainingSeconds({DateTime? now}) {
    if (running && endsAtEpochMs != null) {
      final ms = endsAtEpochMs! - (now ?? DateTime.now()).millisecondsSinceEpoch;
      return ms <= 0 ? 0 : (ms / 1000).ceil();
    }
    return pausedRemainingSeconds;
  }

  Map<String, Object?> toMap() => {
        'durationSeconds': durationSeconds,
        'endsAtEpochMs': endsAtEpochMs,
        'pausedRemainingSeconds': pausedRemainingSeconds,
        'label': label,
        'running': running,
      };

  static CountdownTimerState fromMap(Map map) => CountdownTimerState(
        durationSeconds: map['durationSeconds'] as int? ?? 300,
        endsAtEpochMs: map['endsAtEpochMs'] as int?,
        pausedRemainingSeconds: map['pausedRemainingSeconds'] as int? ?? 300,
        label: map['label']?.toString() ?? 'Timer',
        running: map['running'] as bool? ?? false,
      );
}

class TimerRepository {
  Box get _box => FeatureHiveStore.box(FeatureHiveBoxes.clockTimerState);

  CountdownTimerState state() {
    final raw = _box.get('state');
    if (raw is Map) {
      final s = CountdownTimerState.fromMap(raw);
      // If a running timer has elapsed while we were away, settle it to idle.
      if (s.running && s.remainingSeconds() <= 0) {
        return CountdownTimerState(
          durationSeconds: s.durationSeconds,
          endsAtEpochMs: null,
          pausedRemainingSeconds: s.durationSeconds,
          label: s.label,
          running: false,
        );
      }
      return s;
    }
    return CountdownTimerState.idle;
  }

  Future<void> _save(CountdownTimerState s) => _box.put('state', s.toMap());

  Future<void> start(Duration duration, String label) async {
    final endsAt =
        DateTime.now().add(duration).millisecondsSinceEpoch;
    await _save(CountdownTimerState(
      durationSeconds: duration.inSeconds,
      endsAtEpochMs: endsAt,
      pausedRemainingSeconds: duration.inSeconds,
      label: label.trim().isEmpty ? 'Timer' : label.trim(),
      running: true,
    ));
    await _scheduleNative(endsAt, label);
  }

  Future<void> pause() async {
    final s = state();
    if (!s.running) return;
    await LauncherService.cancelSmartAlarm(kLauncherTimerId);
    await _save(CountdownTimerState(
      durationSeconds: s.durationSeconds,
      endsAtEpochMs: null,
      pausedRemainingSeconds: s.remainingSeconds(),
      label: s.label,
      running: false,
    ));
  }

  Future<void> resume() async {
    final s = state();
    if (s.running || s.pausedRemainingSeconds <= 0) return;
    final endsAt = DateTime.now()
        .add(Duration(seconds: s.pausedRemainingSeconds))
        .millisecondsSinceEpoch;
    await _save(CountdownTimerState(
      durationSeconds: s.durationSeconds,
      endsAtEpochMs: endsAt,
      pausedRemainingSeconds: s.pausedRemainingSeconds,
      label: s.label,
      running: true,
    ));
    await _scheduleNative(endsAt, s.label);
  }

  Future<void> cancel() async {
    final s = state();
    await LauncherService.cancelSmartAlarm(kLauncherTimerId);
    await _save(CountdownTimerState(
      durationSeconds: s.durationSeconds,
      endsAtEpochMs: null,
      pausedRemainingSeconds: s.durationSeconds,
      label: s.label,
      running: false,
    ));
  }

  /// Persists the configured (not yet started) duration so the picker sticks.
  Future<void> setConfigured(Duration duration, String label) async {
    final s = state();
    if (s.running) return;
    await _save(CountdownTimerState(
      durationSeconds: duration.inSeconds,
      endsAtEpochMs: null,
      pausedRemainingSeconds: duration.inSeconds,
      label: label.trim().isEmpty ? 'Timer' : label.trim(),
      running: false,
    ));
  }

  Future<void> _scheduleNative(int triggerAtMillis, String label) async {
    if (!await LauncherService.canScheduleExactAlarms()) return;
    await LauncherService.scheduleSmartAlarm(
      id: kLauncherTimerId,
      triggerAtMillis: triggerAtMillis,
      label: label.trim().isEmpty ? 'Timer' : label.trim(),
      autoSilenceMinutes: 5,
      kind: 'timer',
    );
  }
}

// ---- Stopwatch ------------------------------------------------------------

class StopwatchStateData {
  final int accumulatedMs;

  /// Epoch millis when the current run segment began (null when paused).
  final int? startedAtEpochMs;
  final bool running;

  /// Total elapsed ms at the moment each lap was recorded.
  final List<int> laps;

  const StopwatchStateData({
    required this.accumulatedMs,
    required this.startedAtEpochMs,
    required this.running,
    required this.laps,
  });

  static const idle = StopwatchStateData(
    accumulatedMs: 0,
    startedAtEpochMs: null,
    running: false,
    laps: [],
  );

  int elapsedMs({DateTime? now}) {
    if (running && startedAtEpochMs != null) {
      return accumulatedMs +
          ((now ?? DateTime.now()).millisecondsSinceEpoch - startedAtEpochMs!);
    }
    return accumulatedMs;
  }

  Map<String, Object?> toMap() => {
        'accumulatedMs': accumulatedMs,
        'startedAtEpochMs': startedAtEpochMs,
        'running': running,
        'laps': laps,
      };

  static StopwatchStateData fromMap(Map map) => StopwatchStateData(
        accumulatedMs: map['accumulatedMs'] as int? ?? 0,
        startedAtEpochMs: map['startedAtEpochMs'] as int?,
        running: map['running'] as bool? ?? false,
        laps: (map['laps'] as List?)?.cast<int>() ?? const [],
      );
}

class StopwatchRepository {
  Box get _box => FeatureHiveStore.box(FeatureHiveBoxes.clockStopwatchState);

  StopwatchStateData state() {
    final raw = _box.get('state');
    return raw is Map ? StopwatchStateData.fromMap(raw) : StopwatchStateData.idle;
  }

  Future<void> _save(StopwatchStateData s) => _box.put('state', s.toMap());

  Future<void> startOrResume() async {
    final s = state();
    if (s.running) return;
    await _save(StopwatchStateData(
      accumulatedMs: s.accumulatedMs,
      startedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      running: true,
      laps: s.laps,
    ));
  }

  Future<void> pause() async {
    final s = state();
    if (!s.running) return;
    await _save(StopwatchStateData(
      accumulatedMs: s.elapsedMs(),
      startedAtEpochMs: null,
      running: false,
      laps: s.laps,
    ));
  }

  Future<void> reset() => _save(StopwatchStateData.idle);

  Future<void> lap() async {
    final s = state();
    if (!s.running) return;
    await _save(StopwatchStateData(
      accumulatedMs: s.accumulatedMs,
      startedAtEpochMs: s.startedAtEpochMs,
      running: true,
      laps: [...s.laps, s.elapsedMs()],
    ));
  }
}

class VaultRepository {
  Box get _albums => FeatureHiveStore.box(FeatureHiveBoxes.vaultAlbums);
  Box get _items => FeatureHiveStore.box(FeatureHiveBoxes.vaultItems);

  Future<void> ensureDefaults() async {
    if (_albums.isNotEmpty) return;
    await _albums.putAll({
      'photos': {'schema': 1, 'id': 'photos', 'name': 'Photos'},
      'videos': {'schema': 1, 'id': 'videos', 'name': 'Videos'},
      'documents': {'schema': 1, 'id': 'documents', 'name': 'Documents'},
      'notes': {'schema': 1, 'id': 'notes', 'name': 'Private Notes'},
    });
  }

  List<Map<String, Object?>> albums() => _albums.values
      .whereType<Map>()
      .map((e) => e.cast<String, Object?>())
      .toList(growable: false);

  List<Map<String, Object?>> items() => _items.values
      .whereType<Map>()
      .map((e) => e.cast<String, Object?>())
      .toList(growable: false)
    ..sort((a, b) =>
        (b['createdAt'] as int? ?? 0).compareTo(a['createdAt'] as int? ?? 0));

  Future<void> addNativeImport(Map<String, dynamic> data) async {
    final name = data['name']?.toString() ?? 'Locked file';
    final albumId = _albumForName(name);
    await _items.put(data['id'], {
      'schema': 1,
      'id': data['id'],
      'albumId': albumId,
      'name': name,
      'size': data['size'] ?? 0,
      'createdAt': data['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> deleteItem(String id) => _items.delete(id);

  String _albumForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.mp4') || lower.endsWith('.mov')) return 'videos';
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp')) {
      return 'photos';
    }
    return 'documents';
  }
}

class MiniAppPolicyRepository {
  Box get _appLock => FeatureHiveStore.box(FeatureHiveBoxes.appLockPolicy);
  Box get _hidden => FeatureHiveStore.box(FeatureHiveBoxes.hiddenSpace);
  Box get _intruder => FeatureHiveStore.box(FeatureHiveBoxes.intruderAttempts);

  bool get lockNewApps => _appLock.get('lockNewApps', defaultValue: false);
  String get relockPolicy =>
      _appLock.get('relockPolicy', defaultValue: 'screen_off').toString();
  String get disguise =>
      _hidden.get('disguise', defaultValue: 'App Hider').toString();

  Future<void> setLockNewApps(bool value) => _appLock.put('lockNewApps', value);

  Future<void> setRelockPolicy(String value) =>
      _appLock.put('relockPolicy', value);

  Future<void> setDisguise(String value) => _hidden.put('disguise', value);

  Future<void> addIntruderAttempt(String packageName) => _intruder.put(
        _uuid.v4(),
        {
          'schema': 1,
          'packageName': packageName,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        },
      );

  List<Map<String, Object?>> intruderAttempts() => _intruder.values
      .whereType<Map>()
      .map((e) => e.cast<String, Object?>())
      .toList(growable: false);
}
