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
    'octagon': OctagonShape(),
    'diamond': DiamondShape(),
    'cupertino': CupertinoShape(),
    'leaf': LeafShape(),
  };

  static IconShape forKey(String key) => builtIn[key] ?? const SquircleShape();
}

class CircleShape extends IconShape {
  const CircleShape();
  @override
  Path getMaskPath(double size) {
    return Path()..addOval(Rect.fromLTWH(0, 0, size, size));
  }
}

class SquircleShape extends IconShape {
  const SquircleShape();
  @override
  Path getMaskPath(double size) {
    final r = size / 2;
    final c = size / 2;
    // Superellipse n=5 approximation
    final path = Path();
    const n = 5.0;
    const steps = 120;
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

class RoundedSquareShape extends IconShape {
  const RoundedSquareShape();
  @override
  Path getMaskPath(double size) {
    final r = size * 0.22;
    return Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size, size), Radius.circular(r)));
  }
}

class SquareShape extends IconShape {
  const SquareShape();
  @override
  Path getMaskPath(double size) {
    return Path()..addRect(Rect.fromLTWH(0, 0, size, size));
  }
}

class CupertinoShape extends IconShape {
  const CupertinoShape();
  @override
  Path getMaskPath(double size) {
    final r = size * 0.224;
    return Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size, size), Radius.circular(r)));
  }
}

class TeardropShape extends IconShape {
  const TeardropShape();
  @override
  Path getMaskPath(double size) {
    final path = Path();
    final r = size / 2;
    path.moveTo(r, 0);
    path.cubicTo(size * 0.85, 0, size, size * 0.15, size, r);
    path.cubicTo(size, size * 0.85, size * 0.85, size, r, size);
    path.cubicTo(size * 0.15, size, 0, size * 0.85, 0, r);
    path.cubicTo(0, size * 0.15, size * 0.15, 0, r, 0);
    path.close();
    return path;
  }
}

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

class LeafShape extends IconShape {
  const LeafShape();
  @override
  Path getMaskPath(double size) {
    final path = Path();
    path.moveTo(size / 2, 0);
    path.cubicTo(size, 0, size, size / 2, size, size / 2);
    path.cubicTo(size, size, size / 2, size, size / 2, size);
    path.cubicTo(0, size, 0, size / 2, 0, size / 2);
    path.cubicTo(0, 0, size / 2, 0, size / 2, 0);
    path.close();
    return path;
  }
}

