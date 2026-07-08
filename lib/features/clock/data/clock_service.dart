import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Offline timezone + alarm-timing helpers shared by the clock mini-app.
///
/// Everything here is pure / offline: timezone data is bundled via the
/// `timezone` package (DST-correct, half-hour zones), and the next-occurrence
/// math mirrors the Kotlin `AlarmScheduler` so Dart and native agree on when an
/// alarm should fire. Repeat days use [DateTime.weekday] convention
/// (1 = Monday … 7 = Sunday).
class ClockService {
  ClockService._();

  static bool _initialised = false;

  /// Initialise the timezone database and resolve the device's local zone.
  /// Safe to call more than once. Falls back to UTC if the platform zone can't
  /// be resolved so the World Clock never crashes.
  static Future<void> init() async {
    if (_initialised) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      try {
        tz.setLocalLocation(tz.getLocation('UTC'));
      } catch (_) {}
    }
    _initialised = true;
  }

  static tz.Location get localLocation => tz.local;

  /// Current time in [zoneId] (IANA id). Returns local time if the id is
  /// unknown so the UI degrades gracefully.
  static tz.TZDateTime nowIn(String zoneId) {
    try {
      return tz.TZDateTime.now(tz.getLocation(zoneId));
    } catch (_) {
      return tz.TZDateTime.now(tz.local);
    }
  }

  /// Offset of [zoneId] relative to the device's local zone, in minutes.
  /// Positive = ahead of local.
  static int offsetMinutesFromLocal(String zoneId) {
    final there = nowIn(zoneId);
    final here = tz.TZDateTime.now(tz.local);
    final diff = there.timeZoneOffset - here.timeZoneOffset;
    return diff.inMinutes;
  }

  /// Human label for a relative offset, e.g. "+5:30 HRS", "-3 HRS", "Same".
  static String offsetLabel(int offsetMinutes) {
    if (offsetMinutes == 0) return 'Same time';
    final sign = offsetMinutes > 0 ? '+' : '-';
    final abs = offsetMinutes.abs();
    final h = abs ~/ 60;
    final m = abs % 60;
    final hm = m == 0 ? '$h' : '$h:${m.toString().padLeft(2, '0')}';
    return '$sign$hm HRS';
  }

  static bool isDayTime(DateTime time) => time.hour >= 6 && time.hour < 19;

  /// Next moment an alarm with [hour]:[minute] and [repeatDays] should fire.
  ///
  /// When [repeatDays] is empty the alarm is one-shot: today if still ahead,
  /// otherwise tomorrow. When it repeats, the soonest selected weekday at/after
  /// [from] is used. Mirrors `AlarmScheduler.nextTriggerFor` on the native side.
  static DateTime nextTrigger({
    required int hour,
    required int minute,
    required List<int> repeatDays,
    DateTime? from,
  }) {
    final now = from ?? DateTime.now();
    if (repeatDays.isEmpty) {
      var t = DateTime(now.year, now.month, now.day, hour, minute);
      if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
      return t;
    }
    for (var add = 0; add <= 7; add++) {
      final day = now.add(Duration(days: add));
      if (!repeatDays.contains(day.weekday)) continue;
      final t = DateTime(day.year, day.month, day.day, hour, minute);
      if (t.isAfter(now)) return t;
    }
    // Unreachable in practice; keep it safe.
    return DateTime(now.year, now.month, now.day, hour, minute)
        .add(const Duration(days: 1));
  }

  /// "in 8h 20m" / "in 3d 2h" / "in 45m" / "in less than a minute".
  static String humanizeUntil(DateTime target, {DateTime? from}) {
    final now = from ?? DateTime.now();
    final diff = target.difference(now);
    if (diff.isNegative) return 'now';
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;
    if (days > 0) return 'in ${days}d ${hours}h';
    if (hours > 0) return 'in ${hours}h ${minutes}m';
    if (minutes > 0) return 'in ${minutes}m';
    return 'in less than a minute';
  }

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Short label for the selected repeat days: "Every day", "Weekdays",
  /// "Weekends", "Once", or e.g. "Mon, Wed, Fri".
  static String repeatLabel(List<int> repeatDays) {
    if (repeatDays.isEmpty) return 'Once';
    final set = repeatDays.toSet();
    if (set.length == 7) return 'Every day';
    if (set.length == 5 && set.containsAll({1, 2, 3, 4, 5})) return 'Weekdays';
    if (set.length == 2 && set.containsAll({6, 7})) return 'Weekends';
    final sorted = repeatDays.toList()..sort();
    return sorted.map((d) => _dayNames[(d - 1).clamp(0, 6)]).join(', ');
  }
}
