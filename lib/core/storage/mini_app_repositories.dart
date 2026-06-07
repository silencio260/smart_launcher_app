import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import 'package:smart_launcher_app/features/clock/data/clock_service.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/core/storage/feature_hive_store.dart';
import 'package:smart_launcher_app/features/clock/data/world_cities.dart';

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
  /// Reserved id for the throwaway "test alarm" fired from the Alarms tab. It
  /// is never persisted as a saved alarm and is skipped by the fired-alarm
  /// sync, so it never shows up in the list or disables a real alarm.
  static const String testAlarmId = '__alarm_test__';
  static const String goodMorningTestAlarmId = '__alarm_good_morning_test__';

  Box get _alarms => FeatureHiveStore.box(FeatureHiveBoxes.clockAlarms);
  Box get _cities => FeatureHiveStore.box(FeatureHiveBoxes.clockWorldCities);
  Box get _timers => FeatureHiveStore.box(FeatureHiveBoxes.clockTimerPresets);

  List<ClockAlarmRecord> alarms() => _alarms.values
      .whereType<Map>()
      .map(ClockAlarmRecord.fromMap)
      .where((a) => a.id != testAlarmId)
      .toList()
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
        if (id == testAlarmId || id == goodMorningTestAlarmId) continue;
        final existing = alarm(id);
        if (existing != null &&
            existing.repeatDays.isEmpty &&
            existing.enabled) {
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
      final ms =
          endsAtEpochMs! - (now ?? DateTime.now()).millisecondsSinceEpoch;
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
    final endsAt = DateTime.now().add(duration).millisecondsSinceEpoch;
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
    return raw is Map
        ? StopwatchStateData.fromMap(raw)
        : StopwatchStateData.idle;
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

  /// The single seeded folder that always exists and can't be deleted. Every
  /// import lands here unless the user opened another folder first.
  static const allAlbumId = 'all';

  /// Folders that can never be deleted.
  static const defaultAlbumIds = {allAlbumId};

  /// Where items fall back to when their folder is deleted.
  static const fallbackAlbumId = allAlbumId;

  /// Legacy seeded folders from the previous multi-album scheme. Consolidated
  /// into [allAlbumId] on first run by [ensureDefaults].
  static const _legacyDefaultIds = {'photos', 'videos', 'documents', 'notes'};

  Future<void> ensureDefaults() async {
    // Always guarantee the "All" folder exists.
    if (!_albums.containsKey(allAlbumId)) {
      await _albums.put(
        allAlbumId,
        {'schema': 1, 'id': allAlbumId, 'name': 'All'},
      );
    }
    // Migrate any old default folders: move their items into "All", drop them.
    for (final legacy in _legacyDefaultIds) {
      if (!_albums.containsKey(legacy)) continue;
      for (final item in itemsIn(legacy)) {
        final updated = Map<String, Object?>.from(item);
        updated['albumId'] = allAlbumId;
        await _items.put(updated['id'], updated);
      }
      await _albums.delete(legacy);
    }
  }

  List<Map<String, Object?>> albums() {
    final all = _albums.values
        .whereType<Map>()
        .map((e) => e.cast<String, Object?>())
        .toList(growable: false);
    // Keep "All" first, then user folders alphabetically.
    all.sort((a, b) {
      if (a['id'] == allAlbumId) return -1;
      if (b['id'] == allAlbumId) return 1;
      return (a['name']?.toString() ?? '')
          .toLowerCase()
          .compareTo((b['name']?.toString() ?? '').toLowerCase());
    });
    return all;
  }

  List<Map<String, Object?>> items() => _items.values
      .whereType<Map>()
      .map((e) => e.cast<String, Object?>())
      .toList(growable: false)
    ..sort((a, b) =>
        (b['createdAt'] as int? ?? 0).compareTo(a['createdAt'] as int? ?? 0));

  /// Items belonging to [albumId], newest first. The "All" folder shows every
  /// item regardless of its folder.
  List<Map<String, Object?>> itemsIn(String albumId) => albumId == allAlbumId
      ? items()
      : items()
          .where((item) => item['albumId'] == albumId)
          .toList(growable: false);

  int countIn(String albumId) => albumId == allAlbumId
      ? _items.length
      : _items.values
          .whereType<Map>()
          .where((e) => e['albumId'] == albumId)
          .length;

  /// The newest image/video in [albumId], used as a folder's cover thumbnail.
  /// Returns null when the folder has no previewable media (cards then show the
  /// plain folder icon).
  Map<String, Object?>? coverItem(String albumId) {
    for (final item in itemsIn(albumId)) {
      final kind = item['kind']?.toString();
      if (kind == 'image' || kind == 'video') return item;
    }
    return null;
  }

  /// Creates a user folder and returns its generated id.
  Future<String> addAlbum(String name) async {
    final id = 'album_${_uuid.v4()}';
    await _albums.put(id, {'schema': 1, 'id': id, 'name': name.trim()});
    return id;
  }

  Future<void> renameAlbum(String id, String name) async {
    final raw = _albums.get(id);
    if (raw is! Map) return;
    final updated = raw.cast<String, Object?>();
    updated['name'] = name.trim();
    await _albums.put(id, updated);
  }

  /// Deletes a user folder. The "All" folder is protected; any items inside the
  /// removed folder are reassigned to [fallbackAlbumId] so files are never lost.
  Future<void> deleteAlbum(String id) async {
    if (defaultAlbumIds.contains(id) || !_albums.containsKey(id)) return;
    for (final item in itemsIn(id)) {
      final updated = Map<String, Object?>.from(item);
      updated['albumId'] = fallbackAlbumId;
      await _items.put(updated['id'], updated);
    }
    await _albums.delete(id);
  }

  /// Moves [ids] into [albumId]. Used by bulk selection.
  Future<void> moveItems(Iterable<String> ids, String albumId) async {
    final target = _albums.containsKey(albumId) ? albumId : allAlbumId;
    for (final id in ids) {
      final raw = _items.get(id);
      if (raw is! Map) continue;
      final updated = raw.cast<String, Object?>();
      updated['albumId'] = target;
      await _items.put(id, updated);
    }
  }

  /// Deletes [ids] from both the encrypted native store and local metadata.
  Future<void> deleteItems(Iterable<String> ids) async {
    for (final id in ids) {
      await LauncherService.deleteLockedFile(id);
      await _items.delete(id);
    }
  }

  /// Persists a freshly imported native file. When [albumId] is given the item
  /// lands there; otherwise it goes to the "All" folder.
  Future<void> addNativeImport(
    Map<String, dynamic> data, {
    String? albumId,
  }) async {
    final name = data['name']?.toString() ?? 'Locked file';
    final target = (albumId != null && _albums.containsKey(albumId))
        ? albumId
        : allAlbumId;
    await _items.put(data['id'], {
      'schema': 1,
      'id': data['id'],
      'albumId': target,
      'name': name,
      'size': data['size'] ?? 0,
      'kind': data['kind']?.toString() ?? 'file',
      'mime': data['mime']?.toString() ?? '',
      'createdAt': data['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Pulls the native file list and records any encrypted files that aren't yet
  /// tracked in metadata into [targetAlbumId]. This is how imports are picked up
  /// after the picker returns (the picker runs in its own task, so it can't
  /// hand a result straight back through the method channel).
  ///
  /// Returns the number of newly-added items.
  Future<int> reconcileNativeImports(String targetAlbumId) async {
    final native = await LauncherService.listLockedFiles();
    final target =
        _albums.containsKey(targetAlbumId) ? targetAlbumId : allAlbumId;
    var added = 0;
    for (final file in native) {
      final id = file['id']?.toString();
      if (id == null || id.isEmpty || _items.containsKey(id)) continue;
      await _items.put(id, {
        'schema': 1,
        'id': id,
        'albumId': target,
        'name': file['name']?.toString() ?? 'Locked file',
        'size': file['size'] ?? 0,
        'kind': file['kind']?.toString() ?? 'file',
        'mime': file['mime']?.toString() ?? '',
        'createdAt': file['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      });
      added++;
    }
    return added;
  }

  Future<void> deleteItem(String id) => _items.delete(id);
}

/// Stores the vault's own PIN/pattern credential (salted SHA-256 hash) plus the
/// biometric and auto-lock preferences. Backed by an encrypted Hive box.
class VaultSecurityRepository {
  Box get _box => FeatureHiveStore.box(FeatureHiveBoxes.vaultSecurity);

  static const typePin = 'pin';
  static const typePattern = 'pattern';

  bool get isConfigured => (_box.get('hash') as String?)?.isNotEmpty ?? false;

  /// `pin` or `pattern`. Defaults to `pin` before setup.
  String get type => _box.get('type', defaultValue: typePin).toString();

  bool get biometricEnabled =>
      _box.get('biometric', defaultValue: false) as bool;

  /// When true, importing a file deletes the original from the gallery (a true
  /// "hide"). Defaults to on. On Android 11+ the system shows a confirm dialog.
  bool get removeOriginals =>
      _box.get('removeOriginals', defaultValue: true) as bool;

  /// Grace window in ms during which re-opening the vault skips the prompt.
  /// 0 = always lock immediately.
  int get autoLockMs =>
      (_box.get('autoLockMs', defaultValue: 0) as num).toInt();

  bool get withinGrace {
    final grace = autoLockMs;
    if (grace <= 0) return false;
    final last = (_box.get('lastUnlockAt', defaultValue: 0) as num).toInt();
    if (last == 0) return false;
    return DateTime.now().millisecondsSinceEpoch - last < grace;
  }

  /// Hashes [code] with a fresh random salt and stores it under [type].
  Future<void> setCredential(String type, String code) async {
    final salt = _randomSalt();
    await _box.put('type', type);
    await _box.put('salt', salt);
    await _box.put('hash', _hash(code, salt));
    await _box.put('lastUnlockAt', 0);
  }

  bool verify(String code) {
    final salt = _box.get('salt') as String?;
    final hash = _box.get('hash') as String?;
    if (salt == null || hash == null) return false;
    return _constantTimeEquals(_hash(code, salt), hash);
  }

  Future<void> setBiometricEnabled(bool value) => _box.put('biometric', value);

  Future<void> setRemoveOriginals(bool value) =>
      _box.put('removeOriginals', value);

  Future<void> setAutoLockMs(int value) => _box.put('autoLockMs', value);

  Future<void> markUnlocked() =>
      _box.put('lastUnlockAt', DateTime.now().millisecondsSinceEpoch);

  String _hash(String code, String salt) =>
      sha256.convert(utf8.encode('$salt::$code')).toString();

  String _randomSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64Encode(bytes);
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// App Lock's own PIN/pattern + fingerprint credential — separate from the
/// Vault's, stored in the (otherwise unused) [FeatureHiveBoxes.appLockPolicy]
/// box. Mirrors the Vault's salted-SHA-256 scheme so the in-launcher screens
/// ([AppLockLockScreen]/[AppLockSettingsScreen]) reuse the same flow.
///
/// Critically, every credential write is also **mirrored to native** via
/// [LauncherService.setAppLockCredential] so the device-wide lock overlay (which
/// runs with no Flutter engine) can recompute and verify the identical hash.
class AppLockSecurityRepository {
  Box get _box => FeatureHiveStore.box(FeatureHiveBoxes.appLockPolicy);

  static const typePin = 'pin';
  static const typePattern = 'pattern';

  bool get isConfigured => (_box.get('hash') as String?)?.isNotEmpty ?? false;

  /// `pin` or `pattern`. Defaults to `pin` before setup.
  String get type => _box.get('type', defaultValue: typePin).toString();

  bool get biometricEnabled =>
      _box.get('biometric', defaultValue: false) as bool;

  /// Grace window in ms during which re-opening App Lock skips the prompt.
  /// 0 = always lock immediately.
  int get autoLockMs =>
      (_box.get('autoLockMs', defaultValue: 0) as num).toInt();

  bool get withinGrace {
    final grace = autoLockMs;
    if (grace <= 0) return false;
    final last = (_box.get('lastUnlockAt', defaultValue: 0) as num).toInt();
    if (last == 0) return false;
    return DateTime.now().millisecondsSinceEpoch - last < grace;
  }

  /// Hashes [code] with a fresh random salt, stores it, and mirrors the
  /// `type`/`salt`/`hash` to native so the overlay can verify it.
  Future<void> setCredential(String type, String code) async {
    final salt = _randomSalt();
    final hash = _hash(code, salt);
    await _box.put('type', type);
    await _box.put('salt', salt);
    await _box.put('hash', hash);
    await _box.put('lastUnlockAt', 0);
    await LauncherService.setAppLockCredential(
      type: type,
      salt: salt,
      hash: hash,
    );
  }

  bool verify(String code) {
    final salt = _box.get('salt') as String?;
    final hash = _box.get('hash') as String?;
    if (salt == null || hash == null) return false;
    return _constantTimeEquals(_hash(code, salt), hash);
  }

  Future<void> setBiometricEnabled(bool value) async {
    await _box.put('biometric', value);
    await LauncherService.setAppLockBiometricEnabled(value);
  }

  Future<void> setAutoLockMs(int value) => _box.put('autoLockMs', value);

  Future<void> markUnlocked() =>
      _box.put('lastUnlockAt', DateTime.now().millisecondsSinceEpoch);

  /// Fully removes the App Lock credential, locally and natively.
  Future<void> clear() async {
    await _box.delete('type');
    await _box.delete('salt');
    await _box.delete('hash');
    await _box.delete('biometric');
    await _box.delete('lastUnlockAt');
    await LauncherService.clearAppLockCredential();
  }

  String _hash(String code, String salt) =>
      sha256.convert(utf8.encode('$salt::$code')).toString();

  String _randomSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64Encode(bytes);
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// App Hider's own PIN/pattern + fingerprint credential, separate from the Vault
/// and App Lock. Stored in the [FeatureHiveBoxes.hiddenSpace] box (alongside the
/// disguise key, which it leaves untouched), using the same salted-SHA-256
/// scheme as [VaultSecurityRepository] so the in-launcher setup/unlock flow can
/// reuse the Vault's screens.
///
/// Unlike App Lock there is **no native mirror**: hiding apps is purely a
/// launcher concern (the drawer/search read [LauncherSettings.hiddenApps]), so
/// the credential only ever gates the in-app management screen.
class AppHiderSecurityRepository {
  Box get _box => FeatureHiveStore.box(FeatureHiveBoxes.hiddenSpace);

  static const typePin = 'pin';
  static const typePattern = 'pattern';

  bool get isConfigured => (_box.get('hash') as String?)?.isNotEmpty ?? false;

  /// `pin` or `pattern`. Defaults to `pin` before setup.
  String get type => _box.get('type', defaultValue: typePin).toString();

  bool get biometricEnabled =>
      _box.get('biometric', defaultValue: false) as bool;

  /// Grace window in ms during which re-opening App Hider skips the prompt.
  /// 0 = always lock immediately.
  int get autoLockMs =>
      (_box.get('autoLockMs', defaultValue: 0) as num).toInt();

  bool get withinGrace {
    final grace = autoLockMs;
    if (grace <= 0) return false;
    final last = (_box.get('lastUnlockAt', defaultValue: 0) as num).toInt();
    if (last == 0) return false;
    return DateTime.now().millisecondsSinceEpoch - last < grace;
  }

  /// Hashes [code] with a fresh random salt and stores it under [type].
  Future<void> setCredential(String type, String code) async {
    final salt = _randomSalt();
    await _box.put('type', type);
    await _box.put('salt', salt);
    await _box.put('hash', _hash(code, salt));
    await _box.put('lastUnlockAt', 0);
  }

  bool verify(String code) {
    final salt = _box.get('salt') as String?;
    final hash = _box.get('hash') as String?;
    if (salt == null || hash == null) return false;
    return _constantTimeEquals(_hash(code, salt), hash);
  }

  Future<void> setBiometricEnabled(bool value) => _box.put('biometric', value);

  Future<void> setAutoLockMs(int value) => _box.put('autoLockMs', value);

  Future<void> markUnlocked() =>
      _box.put('lastUnlockAt', DateTime.now().millisecondsSinceEpoch);

  /// Removes the App Hider passcode. Leaves the `disguise` preference (and any
  /// already-hidden apps, which live in [LauncherSettings]) untouched.
  Future<void> clear() async {
    await _box.delete('type');
    await _box.delete('salt');
    await _box.delete('hash');
    await _box.delete('biometric');
    await _box.delete('lastUnlockAt');
  }

  String _hash(String code, String salt) =>
      sha256.convert(utf8.encode('$salt::$code')).toString();

  String _randomSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64Encode(bytes);
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

class MiniAppPolicyRepository {
  Box get _hidden => FeatureHiveStore.box(FeatureHiveBoxes.hiddenSpace);

  String get disguise =>
      _hidden.get('disguise', defaultValue: 'App Hider').toString();

  Future<void> setDisguise(String value) => _hidden.put('disguise', value);
}
