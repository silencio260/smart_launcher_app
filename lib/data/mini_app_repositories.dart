import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../services/launcher_service.dart';
import 'feature_hive_store.dart';

const _uuid = Uuid();

class ClockAlarmRecord {
  final String id;
  final int hour;
  final int minute;
  final String label;
  final bool enabled;
  final List<int> repeatDays;
  final bool vibrate;
  final int snoozeMinutes;
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
  });

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  Map<String, Object?> toMap() => {
        'schema': 1,
        'id': id,
        'hour': hour,
        'minute': minute,
        'label': label,
        'enabled': enabled,
        'repeatDays': repeatDays,
        'vibrate': vibrate,
        'snoozeMinutes': snoozeMinutes,
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
        createdAt:
            map['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      );
}

class ClockRepository {
  Box get _alarms => FeatureHiveStore.box(FeatureHiveBoxes.clockAlarms);
  Box get _cities => FeatureHiveStore.box(FeatureHiveBoxes.clockWorldCities);
  Box get _timers => FeatureHiveStore.box(FeatureHiveBoxes.clockTimerPresets);

  List<ClockAlarmRecord> alarms() =>
      _alarms.values.whereType<Map>().map(ClockAlarmRecord.fromMap).toList()
        ..sort((a, b) => a.hour == b.hour
            ? a.minute.compareTo(b.minute)
            : a.hour.compareTo(b.hour));

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

  Future<void> deleteAlarm(String id) => _alarms.delete(id);

  Future<void> rescheduleEnabledAlarms() async {
    try {
      if (!await LauncherService.canScheduleExactAlarms()) return;
      for (final alarm in alarms().where((alarm) => alarm.enabled)) {
        final now = DateTime.now();
        var trigger = DateTime(
          now.year,
          now.month,
          now.day,
          alarm.hour,
          alarm.minute,
        );
        if (!trigger.isAfter(now)) {
          trigger = trigger.add(const Duration(days: 1));
        }
        await LauncherService.scheduleSmartAlarm(
          id: alarm.id,
          triggerAtMillis: trigger.millisecondsSinceEpoch,
          label: alarm.label,
        );
      }
    } catch (_) {}
  }

  List<Map<String, Object?>> worldCities() {
    if (_cities.isEmpty) {
      _cities.putAll({
        'london': {'city': 'London', 'offset': 0},
        'paris': {'city': 'Paris', 'offset': 1},
        'new_york': {'city': 'New York', 'offset': -5},
        'lagos': {'city': 'Lagos', 'offset': 1},
      });
    }
    return _cities.values
        .whereType<Map>()
        .map((e) => e.cast<String, Object?>())
        .toList(growable: false);
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
