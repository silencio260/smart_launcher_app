import 'package:flutter/material.dart';

class DotRenderer extends StatelessWidget {
  final int count;
  final Color dotColor;
  final Color textColor;
  final bool showCount;
  final double iconSize;

  const DotRenderer({
    super.key,
    required this.count,
    this.dotColor = Colors.red,
    this.textColor = Colors.white,
    this.showCount = true,
    this.iconSize = 48,
  });

  @override
  Widget build(BuildContext context) {
    final dotSize = iconSize * 0.28;
    return Positioned(
      top: 0,
      right: 0,
      child: CustomPaint(
        size: Size(dotSize, dotSize),
        painter: _DotPainter(
          count: count,
          dotColor: dotColor,
          textColor: textColor,
          showCount: showCount,
        ),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  final int count;
  final Color dotColor;
  final Color textColor;
  final bool showCount;

  const _DotPainter({
    required this.count,
    required this.dotColor,
    required this.textColor,
    required this.showCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = dotColor;
    final r = size.width / 2;
    canvas.drawCircle(Offset(r, r), r, paint);

    if (showCount && count > 0) {
      final label = count > 99 ? '99+' : count.toString();
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: textColor,
            fontSize: size.width * 0.55,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.count != count ||
      old.dotColor != dotColor ||
      old.showCount != showCount;
}
