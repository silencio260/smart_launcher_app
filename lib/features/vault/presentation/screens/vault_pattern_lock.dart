import 'package:flutter/material.dart';

import 'package:smart_launcher_app/core/widgets/mini_app_chrome.dart';

/// A monochrome 3x3 pattern lock. Drag across the dots to connect them; on
/// release it reports the ordered node sequence (0..8, row-major) via
/// [onComplete] and briefly shows the drawn path before clearing.
///
/// Built from scratch (no suitable package in the project). Intentionally
/// minimal: nodes are connected in the order the finger reaches them, with the
/// in-between node auto-added when you swipe straight across it (matching the
/// stock Android behaviour).
class VaultPatternLock extends StatefulWidget {
  final ValueChanged<List<int>> onComplete;
  final double size;

  const VaultPatternLock({
    super.key,
    required this.onComplete,
    this.size = 300,
  });

  @override
  State<VaultPatternLock> createState() => _VaultPatternLockState();
}

class _VaultPatternLockState extends State<VaultPatternLock> {
  final List<int> _selected = [];
  Offset? _cursor;
  bool _locked = false; // ignore input during the post-release flash

  double get _cell => widget.size / 3;
  double get _nodeRadius => widget.size / 16;
  double get _hitRadius => _cell / 2 * 0.7;

  Offset _center(int index) {
    final row = index ~/ 3;
    final col = index % 3;
    return Offset(
      _cell * col + _cell / 2,
      _cell * row + _cell / 2,
    );
  }

  int? _nodeAt(Offset p) {
    for (var i = 0; i < 9; i++) {
      if ((p - _center(i)).distance <= _hitRadius) return i;
    }
    return null;
  }

  /// The node sitting exactly between [a] and [b] on the grid, if any (for
  /// straight swipes like 0→2 or 0→6 that should capture the middle node).
  int? _between(int a, int b) {
    final ar = a ~/ 3, ac = a % 3;
    final br = b ~/ 3, bc = b % 3;
    final mr = ar + br, mc = ac + bc;
    if (mr.isOdd || mc.isOdd) return null;
    return (mr ~/ 2) * 3 + (mc ~/ 2);
  }

  void _addAt(Offset p) {
    final node = _nodeAt(p);
    if (node == null || _selected.contains(node)) return;
    if (_selected.isNotEmpty) {
      final mid = _between(_selected.last, node);
      if (mid != null && !_selected.contains(mid)) _selected.add(mid);
    }
    _selected.add(node);
  }

  void _start(Offset p) {
    if (_locked) return;
    setState(() {
      _selected.clear();
      _cursor = p;
      _addAt(p);
    });
  }

  void _update(Offset p) {
    if (_locked) return;
    setState(() {
      _cursor = p;
      _addAt(p);
    });
  }

  void _end() {
    if (_locked) return;
    final result = List<int>.of(_selected);
    setState(() {
      _cursor = null;
      _locked = true;
    });
    widget.onComplete(result);
    // Clear the drawn path shortly after so the next attempt starts clean.
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _locked = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) => _start(d.localPosition),
      onPanUpdate: (d) => _update(d.localPosition),
      onPanEnd: (_) => _end(),
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _PatternPainter(
          selected: _selected,
          cursor: _cursor,
          center: _center,
          nodeRadius: _nodeRadius,
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  final List<int> selected;
  final Offset? cursor;
  final Offset Function(int) center;
  final double nodeRadius;

  _PatternPainter({
    required this.selected,
    required this.cursor,
    required this.center,
    required this.nodeRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Path between selected nodes, then on to the live cursor.
    for (var i = 0; i < selected.length - 1; i++) {
      canvas.drawLine(center(selected[i]), center(selected[i + 1]), line);
    }
    if (selected.isNotEmpty && cursor != null) {
      canvas.drawLine(center(selected.last), cursor!, line);
    }

    for (var i = 0; i < 9; i++) {
      final c = center(i);
      final on = selected.contains(i);
      // Outer ring.
      canvas.drawCircle(
        c,
        nodeRadius,
        Paint()
          ..color = on ? Colors.white : miniAppMuted
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
      // Filled centre when selected.
      if (on) {
        canvas.drawCircle(
          c,
          nodeRadius * 0.42,
          Paint()..color = Colors.white,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) =>
      old.selected != selected || old.cursor != cursor;
}
