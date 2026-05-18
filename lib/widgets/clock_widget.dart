import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class ClockWidget extends StatefulWidget {
  const ClockWidget({super.key});

  @override
  State<ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<ClockWidget> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _scheduleNextMinuteTick();
  }

  void _scheduleNextMinuteTick() {
    final now = DateTime.now();
    final nextMinute =
        DateTime(now.year, now.month, now.day, now.hour, now.minute)
            .add(const Duration(minutes: 1));
    _timer = Timer(nextMinute.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleNextMinuteTick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _timeText {
    final h = _now.hour;
    final hour = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    final m = _now.minute.toString().padLeft(2, '0');
    return '$hour:$m';
  }

  String get _period => _now.hour >= 12 ? 'PM' : 'AM';

  String get _dateText {
    const days = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    final dow = days[_now.weekday % 7];
    return '$dow  ·  ${months[_now.month - 1]} ${_now.day}';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxByWidth = constraints.maxWidth * 0.30;
        final maxByHeight = constraints.maxHeight * 0.58;
        final timeSize = math.min(maxByWidth, maxByHeight).clamp(28.0, 104.0);
        final periodSize = (timeSize * 0.26).clamp(10.0, 22.0);
        final dateSize = (timeSize * 0.22).clamp(10.0, 16.0);

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _timeText,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: timeSize,
                      fontWeight: FontWeight.w200,
                      letterSpacing: -2,
                      height: 1.0,
                      shadows: const [
                        Shadow(
                          color: Colors.black45,
                          blurRadius: 14,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(
                      left: timeSize * 0.12,
                      bottom: timeSize * 0.12,
                    ),
                    child: Text(
                      _period,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: periodSize,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.5,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: timeSize * 0.14),
              Text(
                _dateText,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: dateSize,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 2.2,
                  shadows: const [
                    Shadow(color: Colors.black38, blurRadius: 6),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
