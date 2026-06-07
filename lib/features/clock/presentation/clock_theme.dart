import 'package:flutter/material.dart';

import 'package:smart_launcher_app/core/widgets/mini_app_chrome.dart';

/// Black & white, One UI-inspired theming local to the clock mini-app.
///
/// The clock app is deliberately monochrome: it reuses the neutral surfaces
/// from [mini_app_chrome.dart] (`miniAppBackground`, `miniAppSurface`,
/// `miniAppSurface2`, `miniAppMuted`) but swaps the shared orange accent for
/// plain white. Nothing here touches the shared constants, so the other
/// mini-apps keep their own accent.
const clockAccent = Colors.white;

/// On = white thumb on a light-gray track; off = muted thumb on a dark track.
/// Overrides the orange switch theme injected by [MiniAppScaffold] so toggles
/// read monochrome.
final clockSwitchTheme = SwitchThemeData(
  thumbColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.selected)
        ? Colors.white
        : miniAppMuted,
  ),
  trackColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.selected)
        ? miniAppMuted
        : miniAppSurface2,
  ),
  trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
);

/// Wraps the ambient theme so in-clock switches and selection states render
/// white instead of the shared orange. Apply with a [Theme] around clock
/// content.
ThemeData clockThemeOf(BuildContext context) {
  final base = Theme.of(context);
  return base.copyWith(
    switchTheme: clockSwitchTheme,
    colorScheme: base.colorScheme.copyWith(primary: Colors.white),
  );
}

/// A rounded dark card, the building block of the One UI clock lists. More
/// rounded than [MiniCard] (radius 20 vs 8) to match the reference.
class ClockCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const ClockCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: miniAppSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: card,
      ),
    );
  }
}

/// Renders a time the One UI way: large `h:mm` digits with a smaller, trailing
/// `am`/`pm` sitting on the same baseline. Honors the device 24-hour setting
/// (24h → no suffix). [color] dims the whole thing for disabled alarms.
class ClockTime extends StatelessWidget {
  final int hour;
  final int minute;
  final Color color;
  final double fontSize;
  final FontWeight weight;

  const ClockTime({
    super.key,
    required this.hour,
    required this.minute,
    this.color = Colors.white,
    this.fontSize = 52,
    this.weight = FontWeight.w300,
  });

  @override
  Widget build(BuildContext context) {
    final use24 = MediaQuery.of(context).alwaysUse24HourFormat;
    final mm = minute.toString().padLeft(2, '0');
    if (use24) {
      return Text(
        '${hour.toString().padLeft(2, '0')}:$mm',
        style: TextStyle(fontSize: fontSize, fontWeight: weight, color: color),
      );
    }
    final isPm = hour >= 12;
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = isPm ? 'pm' : 'am';
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$h12:$mm',
            style:
                TextStyle(fontSize: fontSize, fontWeight: weight, color: color),
          ),
          TextSpan(
            text: ' $suffix',
            style: TextStyle(
              fontSize: fontSize * 0.34,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// The `M T W T F S S` strip shown on repeating alarms: a small dot sits above
/// each active day, active days are white, inactive days muted gray.
class RepeatDaysStrip extends StatelessWidget {
  /// Active weekdays, 1 = Mon … 7 = Sun.
  final Set<int> days;
  final Color activeColor;
  final Color inactiveColor;

  const RepeatDaysStrip({
    super.key,
    required this.days,
    this.activeColor = Colors.white,
    this.inactiveColor = miniAppMuted,
  });

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: days.contains(i + 1)
                      ? activeColor
                      : Colors.transparent,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _labels[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: days.contains(i + 1) ? activeColor : inactiveColor,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
