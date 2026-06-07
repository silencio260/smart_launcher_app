import 'dart:math' as math;
import 'package:flutter/material.dart';

abstract class IconShape {
  const IconShape();
  Path getMaskPath(double size);
  double get iconScale => 1.0;

  static const Map<String, IconShape> builtIn = {
    'circle': CircleShape(),
    'squircle': SquircleShape(),
    'rounded_square': RoundedSquareShape(),
    'square': SquareShape(),
    'teardrop': TeardropShape(),
    'hexagon': HexagonShape(),
    'rounded_hexagon': RoundedHexagonShape(),
    'octagon': OctagonShape(),
    'diamond': DiamondShape(),
    'cupertino': CupertinoShape(),
    'leaf': LeafShape(),
    'egg': EggShape(),
    'sammy': SammyShape(),
    'pebble': PebbleShape(),
    'flower': FlowerShape(),
    'heart': HeartShape(),
    'arch': ArchShape(),
    'cloudy': CloudyShape(),
    'vessel': VesselShape(),
    'four_sided_cookie': FourSidedCookieShape(),
  };

  static IconShape forKey(String key) => builtIn[key] ?? const SquircleShape();
}

// ── Circle ────────────────────────────────────────────────────────────────────

class CircleShape extends IconShape {
  const CircleShape();
  @override
  Path getMaskPath(double size) =>
      Path()..addOval(Rect.fromLTWH(0, 0, size, size));
}

// ── Squircle (superellipse n=4, Lawnchair default) ────────────────────────────
// Uses the exact same superellipse formula as Lawnchair's SquircleShape.

class SquircleShape extends IconShape {
  const SquircleShape();
  @override
  Path getMaskPath(double size) {
    final r = size / 2;
    final c = size / 2;
    const n = 4.0; // Lawnchair uses n=4 (iOS-like squircle)
    const steps = 200;
    final path = Path();
    for (int i = 0; i <= steps; i++) {
      final t = 2 * math.pi * i / steps;
      final cos = math.cos(t);
      final sin = math.sin(t);
      final x = c + r * math.pow(cos.abs(), 2 / n) * (cos >= 0 ? 1.0 : -1.0);
      final y = c + r * math.pow(sin.abs(), 2 / n) * (sin >= 0 ? 1.0 : -1.0);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    return path;
  }
}

// ── Rounded square (22% corner radius) ───────────────────────────────────────

class RoundedSquareShape extends IconShape {
  const RoundedSquareShape();
  @override
  Path getMaskPath(double size) {
    final r = size * 0.22;
    return Path()
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size, size), Radius.circular(r)));
  }
}

// ── Square ────────────────────────────────────────────────────────────────────

class SquareShape extends IconShape {
  const SquareShape();
  @override
  Path getMaskPath(double size) =>
      Path()..addRect(Rect.fromLTWH(0, 0, size, size));
}

// ── Cupertino (iOS 13+ icon radius ≈ 22.4%) ──────────────────────────────────

class CupertinoShape extends IconShape {
  const CupertinoShape();
  @override
  Path getMaskPath(double size) {
    final r = size * 0.224;
    return Path()
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size, size), Radius.circular(r)));
  }
}

// ── Teardrop (pointed top, round bottom) ─────────────────────────────────────

class TeardropShape extends IconShape {
  const TeardropShape();
  @override
  Path getMaskPath(double size) {
    final path = Path();
    path.moveTo(size * 0.5, 0);
    path.cubicTo(size * 0.95, size * 0.12, size, size * 0.45, size, size * 0.6);
    path.cubicTo(size, size * 0.82, size * 0.78, size, size * 0.5, size);
    path.cubicTo(size * 0.22, size, 0, size * 0.82, 0, size * 0.6);
    path.cubicTo(0, size * 0.45, size * 0.05, size * 0.12, size * 0.5, 0);
    path.close();
    return path;
  }
}

// ── Leaf (rounded rect with pointed top-left corner) ─────────────────────────
// Matches the common "leaf" appearance in Lawnchair Neo icon shape pickers.

class LeafShape extends IconShape {
  const LeafShape();
  @override
  Path getMaskPath(double size) {
    final r = size * 0.3;
    final path = Path();
    // top-left: sharp point at (0, 0)
    path.moveTo(0, 0);
    path.lineTo(size - r, 0);
    path.quadraticBezierTo(size, 0, size, r);
    path.lineTo(size, size - r);
    path.quadraticBezierTo(size, size, size - r, size);
    path.lineTo(r, size);
    path.quadraticBezierTo(0, size, 0, size - r);
    path.close();
    return path;
  }
}

// ── Egg (taller-than-wide, rounded top, slightly pointed bottom) ──────────────

class EggShape extends IconShape {
  const EggShape();
  @override
  Path getMaskPath(double size) {
    final path = Path();
    path.moveTo(size * 0.5, 0);
    path.cubicTo(size * 0.85, 0, size, size * 0.38, size, size * 0.55);
    path.cubicTo(size, size * 0.78, size * 0.78, size, size * 0.5, size);
    path.cubicTo(size * 0.22, size, 0, size * 0.78, 0, size * 0.55);
    path.cubicTo(0, size * 0.38, size * 0.15, 0, size * 0.5, 0);
    path.close();
    return path;
  }
}

// ── Hexagon ───────────────────────────────────────────────────────────────────

class HexagonShape extends IconShape {
  const HexagonShape();
  @override
  Path getMaskPath(double size) {
    final path = Path();
    final r = size / 2;
    for (int i = 0; i < 6; i++) {
      final angle = math.pi / 180 * (60 * i - 30);
      final x = r + r * math.cos(angle);
      final y = r + r * math.sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    return path;
  }
}

// ── Rounded hexagon ───────────────────────────────────────────────────────────

class RoundedHexagonShape extends IconShape {
  const RoundedHexagonShape();
  @override
  Path getMaskPath(double size) {
    final path = Path();
    final r = size / 2;
    final cornerR = size * 0.08;
    final pts = List.generate(6, (i) {
      final angle = math.pi / 180 * (60 * i - 30);
      return Offset(r + r * math.cos(angle), r + r * math.sin(angle));
    });
    for (int i = 0; i < 6; i++) {
      final prev = pts[(i + 5) % 6];
      final curr = pts[i];
      final next = pts[(i + 1) % 6];
      final d1 = (curr - prev);
      final d2 = (next - curr);
      final l1 = d1.distance;
      final l2 = d2.distance;
      final t = cornerR;
      final p1 = curr - Offset(d1.dx / l1 * t, d1.dy / l1 * t);
      final p2 = curr + Offset(d2.dx / l2 * t, d2.dy / l2 * t);
      i == 0 ? path.moveTo(p1.dx, p1.dy) : path.lineTo(p1.dx, p1.dy);
      path.quadraticBezierTo(curr.dx, curr.dy, p2.dx, p2.dy);
    }
    path.close();
    return path;
  }
}

// ── Octagon ───────────────────────────────────────────────────────────────────

class OctagonShape extends IconShape {
  const OctagonShape();
  @override
  Path getMaskPath(double size) {
    final path = Path();
    final r = size / 2;
    for (int i = 0; i < 8; i++) {
      final angle = math.pi / 180 * (45 * i - 22.5);
      final x = r + r * math.cos(angle);
      final y = r + r * math.sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    return path;
  }
}

// ── Diamond ───────────────────────────────────────────────────────────────────

class DiamondShape extends IconShape {
  const DiamondShape();
  @override
  Path getMaskPath(double size) {
    final r = size / 2;
    return Path()
      ..moveTo(r, 0)
      ..lineTo(size, r)
      ..lineTo(r, size)
      ..lineTo(0, r)
      ..close();
  }
}

// ── Samsung-style squircle ("sammy") ─────────────────────────────────────────
// Superellipse n=3 — slightly softer than iOS squircle.

class SammyShape extends IconShape {
  const SammyShape();
  @override
  Path getMaskPath(double size) {
    final r = size / 2;
    final c = size / 2;
    const n = 3.0;
    const steps = 200;
    final path = Path();
    for (int i = 0; i <= steps; i++) {
      final t = 2 * math.pi * i / steps;
      final cos = math.cos(t);
      final sin = math.sin(t);
      final x = c + r * math.pow(cos.abs(), 2 / n) * (cos >= 0 ? 1.0 : -1.0);
      final y = c + r * math.pow(sin.abs(), 2 / n) * (sin >= 0 ? 1.0 : -1.0);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    return path;
  }
}

// ── Pebble (asymmetric organic rounded rect) ──────────────────────────────────

class PebbleShape extends IconShape {
  const PebbleShape();
  @override
  Path getMaskPath(double size) {
    final path = Path();
    path.moveTo(size * 0.15, 0);
    path.cubicTo(
        size * 0.45, -size * 0.04, size * 0.7, 0, size * 0.88, size * 0.12);
    path.cubicTo(
        size * 1.04, size * 0.28, size, size * 0.55, size * 0.95, size * 0.78);
    path.cubicTo(
        size * 0.88, size * 1.02, size * 0.6, size, size * 0.35, size * 0.98);
    path.cubicTo(
        size * 0.12, size * 0.96, -size * 0.02, size * 0.8, 0, size * 0.55);
    path.cubicTo(
        -size * 0.02, size * 0.3, size * 0.02, size * 0.06, size * 0.15, 0);
    path.close();
    return path;
  }
}

// ── Flower (6-petal) ──────────────────────────────────────────────────────────

class FlowerShape extends IconShape {
  const FlowerShape();
  @override
  Path getMaskPath(double size) {
    final path = Path();
    final c = size / 2;
    final r = size * 0.28;
    final outer = size * 0.5;
    const petals = 6;
    for (int i = 0; i < petals * 2; i++) {
      final angle = math.pi * i / petals;
      final radius = i.isEven ? outer : r;
      final x = c + radius * math.cos(angle - math.pi / 2);
      final y = c + radius * math.sin(angle - math.pi / 2);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    return path;
  }
}

// ── Heart ──────────────────────────────────────────────────────────────────────

class HeartShape extends IconShape {
  const HeartShape();
  @override
  Path getMaskPath(double size) {
    final path = Path();
    path.moveTo(size * 0.5, size * 0.85);
    path.cubicTo(0, size * 0.55, 0, size * 0.2, size * 0.25, size * 0.2);
    path.cubicTo(size * 0.38, size * 0.2, size * 0.46, size * 0.28, size * 0.5,
        size * 0.38);
    path.cubicTo(size * 0.54, size * 0.28, size * 0.62, size * 0.2, size * 0.75,
        size * 0.2);
    path.cubicTo(size, size * 0.2, size, size * 0.55, size * 0.5, size * 0.85);
    path.close();
    return path;
  }
}

// ── Arch (stadium / rounded-top square) ──────────────────────────────────────

class ArchShape extends IconShape {
  const ArchShape();
  @override
  Path getMaskPath(double size) {
    final r = size * 0.5; // fully rounded top
    return Path()
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, size, size),
        topLeft: Radius.circular(r),
        topRight: Radius.circular(r),
        bottomLeft: const Radius.circular(8),
        bottomRight: const Radius.circular(8),
      ));
  }
}

// ── Cloudy (3 bumps on top) ────────────────────────────────────────────────────

class CloudyShape extends IconShape {
  const CloudyShape();
  @override
  Path getMaskPath(double size) {
    final path = Path();
    final r = size * 0.22;
    path.moveTo(r, size);
    path.lineTo(size - r, size);
    path.quadraticBezierTo(size, size, size, size - r);
    path.lineTo(size, size * 0.5);
    // three top bumps
    path.arcToPoint(Offset(size * 0.67, size * 0.5),
        radius: Radius.circular(size * 0.17), clockwise: false);
    path.arcToPoint(Offset(size * 0.33, size * 0.5),
        radius: Radius.circular(size * 0.17), clockwise: false);
    path.arcToPoint(Offset(0, size * 0.5),
        radius: Radius.circular(size * 0.17), clockwise: false);
    path.lineTo(0, size - r);
    path.quadraticBezierTo(0, size, r, size);
    path.close();
    return path;
  }
}

// ── Vessel (stadium) ──────────────────────────────────────────────────────────

class VesselShape extends IconShape {
  const VesselShape();
  @override
  Path getMaskPath(double size) {
    final r = size * 0.3;
    return Path()
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size, size), Radius.circular(r)));
  }
}

// ── Four-sided cookie (inward-curved square) ──────────────────────────────────

class FourSidedCookieShape extends IconShape {
  const FourSidedCookieShape();
  @override
  Path getMaskPath(double size) {
    final c = size / 2;
    final d = size * 0.18; // inward pull at midpoints
    final path = Path();
    path.moveTo(0, 0);
    path.quadraticBezierTo(c, d, size, 0);
    path.quadraticBezierTo(size - d, c, size, size);
    path.quadraticBezierTo(c, size - d, 0, size);
    path.quadraticBezierTo(d, c, 0, 0);
    path.close();
    return path;
  }
}
