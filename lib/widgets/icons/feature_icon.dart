import 'package:flutter/material.dart';

import '../../models/launcher_feature.dart';

class FeatureIcon extends StatelessWidget {
  final String? featureId;
  final String? packageName;
  final String? componentName;
  final double size;

  const FeatureIcon({
    super.key,
    this.featureId,
    this.packageName,
    this.componentName,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final artwork = LauncherFeatureCatalog.artworkForComponent(componentName) ??
        LauncherFeatureCatalog.artworkForId(featureId) ??
        (packageName == null
            ? null
            : LauncherFeatureCatalog.fromPackage(packageName!) == null
                ? null
                : LauncherFeatureCatalog.artworkForId(
                    LauncherFeatureCatalog.idForPackage(packageName!),
                  )) ??
        const LauncherFeatureArtwork(id: 'fallback', color: Colors.blueGrey);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: artwork.color,
        borderRadius: BorderRadius.circular(size * 0.225),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: size * 0.18,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _FeatureGlyphPainter(artwork.id),
      ),
    );
  }
}

class _FeatureGlyphPainter extends CustomPainter {
  final String artworkId;

  const _FeatureGlyphPainter(this.artworkId);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 108;
    double u(double value) => value * s;
    Rect rect(double l, double t, double r, double b) =>
        Rect.fromLTRB(u(l), u(t), u(r), u(b));
    RRect rrect(
      double l,
      double t,
      double r,
      double b,
      double radius,
    ) =>
        RRect.fromRectAndRadius(rect(l, t, r, b), Radius.circular(u(radius)));
    Offset point(double x, double y) => Offset(u(x), u(y));
    Paint fill(Color color) => Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    Paint stroke(
      Color color,
      double width, {
      StrokeCap cap = StrokeCap.round,
      StrokeJoin join = StrokeJoin.round,
    }) =>
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u(width)
          ..strokeCap = cap
          ..strokeJoin = join
          ..color = color;

    switch (artworkId) {
      case 'file_locker':
        canvas.drawRRect(
            rrect(18, 36, 90, 86, 9), fill(const Color(0xFF1ABC9C)));
        canvas.drawRRect(
            rrect(21, 30, 52, 44, 7), fill(const Color(0xFF29D6B5)));
        canvas.drawArc(
            rect(38, 26, 70, 58), 3.14, 3.14, false, stroke(Colors.white, 7));
        canvas.drawCircle(point(54, 61), u(8), fill(Colors.white));
        canvas.drawRRect(rrect(50, 66, 58, 78, 2), fill(Colors.white));
        return;
      case 'app_hider':
        final eye = Path()
          ..moveTo(u(18), u(54))
          ..cubicTo(u(29), u(34), u(43), u(28), u(54), u(28))
          ..cubicTo(u(65), u(28), u(79), u(34), u(90), u(54))
          ..cubicTo(u(79), u(74), u(65), u(80), u(54), u(80))
          ..cubicTo(u(43), u(80), u(29), u(74), u(18), u(54))
          ..close();
        canvas.drawPath(eye, fill(const Color(0xFF6C63FF)));
        canvas.drawCircle(point(54, 54), u(13), fill(const Color(0xFF101014)));
        canvas.drawLine(point(25, 83), point(83, 25), stroke(Colors.white, 7));
        return;
      case 'app_locker':
        for (final cell in const [
          Rect.fromLTWH(31, 31, 18, 18),
          Rect.fromLTWH(59, 31, 18, 18),
          Rect.fromLTWH(31, 59, 18, 18),
          Rect.fromLTWH(59, 59, 18, 18),
        ]) {
          canvas.drawRect(
            rect(cell.left, cell.top, cell.right, cell.bottom),
            fill(const Color(0xFFEF5350)),
          );
        }
        canvas.drawArc(
            rect(40, 43, 68, 71), 3.14, 3.14, false, stroke(Colors.white, 8));
        canvas.drawRRect(rrect(34, 60, 74, 87, 6), fill(Colors.white));
        return;
      case 'clock':
        canvas.drawCircle(point(54, 54), u(36), fill(const Color(0xFFF5A623)));
        canvas.drawCircle(point(54, 54), u(27), fill(const Color(0xFF0B0B0D)));
        canvas.drawLine(point(54, 54), point(54, 33), stroke(Colors.white, 6));
        canvas.drawLine(point(54, 54), point(72, 65), stroke(Colors.white, 6));
        return;
      case 'calculator':
        canvas.drawRRect(
            rrect(21, 12, 87, 96, 12), fill(const Color(0xFF2B2B30)));
        canvas.drawRRect(
            rrect(29, 24, 79, 39, 4), fill(const Color(0xFF111114)));
        for (final cell in const [
          Rect.fromLTWH(30, 50, 12, 12),
          Rect.fromLTWH(48, 50, 12, 12),
          Rect.fromLTWH(66, 50, 12, 12),
          Rect.fromLTWH(30, 68, 12, 12),
          Rect.fromLTWH(48, 68, 12, 12),
          Rect.fromLTWH(66, 68, 12, 12),
        ]) {
          canvas.drawRRect(
            rrect(cell.left, cell.top, cell.right, cell.bottom, 2),
            fill(const Color(0xFFF5A623)),
          );
        }
        return;
      case 'notes':
        canvas.drawRRect(rrect(28, 18, 80, 90, 8), fill(Colors.white));
        canvas.drawRRect(
            rrect(28, 18, 80, 33, 8), fill(const Color(0xFFA5B4FC)));
        canvas.drawLine(
            point(39, 47), point(70, 47), stroke(const Color(0xFF312E81), 4));
        canvas.drawLine(
            point(39, 59), point(70, 59), stroke(const Color(0xFF312E81), 4));
        canvas.drawLine(
            point(39, 71), point(62, 71), stroke(const Color(0xFF312E81), 4));
        return;
      case 'weather':
        canvas.drawCircle(point(69, 34), u(15), fill(const Color(0xFFFFD166)));
        canvas.drawCircle(point(44, 63), u(18), fill(Colors.white));
        canvas.drawCircle(point(61, 57), u(22), fill(Colors.white));
        canvas.drawCircle(point(75, 66), u(15), fill(Colors.white));
        canvas.drawRRect(rrect(29, 62, 88, 80, 9), fill(Colors.white));
        return;
      case 'browser':
        canvas.drawCircle(point(54, 54), u(34), fill(const Color(0xFF38BDF8)));
        canvas.drawCircle(point(54, 54), u(25), stroke(Colors.white, 4));
        canvas.drawLine(point(20, 54), point(88, 54), stroke(Colors.white, 4));
        canvas.drawLine(point(54, 20), point(54, 88), stroke(Colors.white, 4));
        final needle = Path()
          ..moveTo(u(66), u(38))
          ..lineTo(u(58), u(63))
          ..lineTo(u(42), u(70))
          ..lineTo(u(50), u(45))
          ..close();
        canvas.drawPath(needle, fill(const Color(0xFF172554)));
        return;
      default:
        final sparkle = Path()
          ..moveTo(u(54), u(22))
          ..lineTo(u(63), u(45))
          ..lineTo(u(86), u(54))
          ..lineTo(u(63), u(63))
          ..lineTo(u(54), u(86))
          ..lineTo(u(45), u(63))
          ..lineTo(u(22), u(54))
          ..lineTo(u(45), u(45))
          ..close();
        canvas.drawPath(sparkle, fill(Colors.white));
        return;
    }
  }

  @override
  bool shouldRepaint(_FeatureGlyphPainter oldDelegate) =>
      oldDelegate.artworkId != artworkId;
}
