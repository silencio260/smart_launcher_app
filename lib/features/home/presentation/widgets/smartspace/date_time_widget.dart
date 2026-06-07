import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smart_launcher_app/core/models/launcher_settings.dart';

class DateTimeWidget extends StatefulWidget {
  final LauncherSettings settings;

  const DateTimeWidget({super.key, required this.settings});

  @override
  State<DateTimeWidget> createState() => _DateTimeWidgetState();
}

class _DateTimeWidgetState extends State<DateTimeWidget> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // PERF: clock format is `h:mm a` / `HH:mm` — no seconds shown, so a 1Hz
    // tick was pure waste. 30s is plenty to keep minute boundaries fresh and
    // stops a 1Hz setState chain that was tripping a CellLayout LayoutBuilder
    // pass + 100-200ms AppWidgetManager IPC stall every second.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeFormat =
        widget.settings.timeFormat == TimeFormat.h12 ? 'h:mm a' : 'HH:mm';
    final timeStr = DateFormat(timeFormat).format(_now);
    final dateStr = DateFormat('EEEE, MMMM d').format(_now);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeStr,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 52,
            fontWeight: FontWeight.w200,
            shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          dateStr,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16,
            fontWeight: FontWeight.w400,
            shadows: [Shadow(blurRadius: 4, color: Colors.black38)],
          ),
        ),
      ],
    );
  }
}
