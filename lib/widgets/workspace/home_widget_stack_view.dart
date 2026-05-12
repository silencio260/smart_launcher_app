import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/launcher_widget_info.dart';
import '../../services/launcher_service.dart';

/// Shows a swipeable stack of widgets. Long-press dragging is handled by the
/// parent CellLayoutView (same as single widgets). Resize handles work on the
/// stack as a whole.
class HomeWidgetStackView extends StatefulWidget {
  final List<LauncherWidgetInfo> widgets;
  final int spanX;
  final int spanY;
  final int page;
  final int slot;
  final int minSpanX;
  final int minSpanY;
  final int maxSpanX;
  final int maxSpanY;
  final int gridColumns;
  final double resizeStepX;
  final double resizeStepY;
  final bool isSelected;
  final VoidCallback onDismissResize;
  final void Function(int slot, int spanX, int spanY) onResize;

  const HomeWidgetStackView({
    super.key,
    required this.widgets,
    required this.spanX,
    required this.spanY,
    required this.page,
    required this.slot,
    required this.minSpanX,
    required this.minSpanY,
    required this.maxSpanX,
    required this.maxSpanY,
    required this.gridColumns,
    required this.resizeStepX,
    required this.resizeStepY,
    required this.isSelected,
    required this.onDismissResize,
    required this.onResize,
  });

  @override
  State<HomeWidgetStackView> createState() => _HomeWidgetStackViewState();
}

class _HomeWidgetStackViewState extends State<HomeWidgetStackView> {
  late PageController _pageController;
  int _currentIndex = 0;
  static const double _frameInset = 6;
  static const double _handleSize = 40;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: PageView.builder(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemCount: widget.widgets.length,
            itemBuilder: (_, i) {
              final w = widget.widgets[i];
              return _WidgetStackItem(appWidgetId: w.appWidgetId);
            },
          ),
        ),
        // Page dots
        if (widget.widgets.length > 1)
          Positioned(
            top: 4,
            left: 0,
            right: 0,
            child: _PageDots(
              count: widget.widgets.length,
              current: _currentIndex,
            ),
          ),
        if (widget.isSelected)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismissResize,
              onPanStart: (_) => widget.onDismissResize(),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
        if (widget.isSelected)
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.all(_frameInset),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.88),
                      width: 1.6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (widget.isSelected) ..._buildResizeHandles(),
      ],
    );
  }

  List<Widget> _buildResizeHandles() {
    const directions = <_ResizeDirection>[
      _ResizeDirection.left,
      _ResizeDirection.top,
      _ResizeDirection.right,
      _ResizeDirection.bottom,
      _ResizeDirection.topLeft,
      _ResizeDirection.topRight,
      _ResizeDirection.bottomLeft,
      _ResizeDirection.bottomRight,
    ];
    return directions.map(_buildHandle).toList();
  }

  Widget _buildHandle(_ResizeDirection direction) {
    return Positioned(
      left: direction.leftInset,
      right: direction.rightInset,
      top: direction.topInset,
      bottom: direction.bottomInset,
      width: direction.handleWidth,
      height: direction.handleHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return _WidgetResizeHandle(
            cursor: direction.cursor,
            alignment: direction.alignment,
            stepX: widget.resizeStepX,
            stepY: widget.resizeStepY,
            onDrag: (dxSteps, dySteps) =>
                _applyResize(direction, dxSteps, dySteps),
          );
        },
      ),
    );
  }

  void _applyResize(_ResizeDirection direction, int dxSteps, int dySteps) {
    if (dxSteps == 0 && dySteps == 0) return;

    var nextSlot = widget.slot;
    var nextSpanX = widget.spanX;
    var nextSpanY = widget.spanY;

    if (direction.affectsLeft && dxSteps != 0) {
      final candidateSlot = nextSlot + dxSteps;
      final candidateSpanX = nextSpanX - dxSteps;
      if (candidateSpanX >= widget.minSpanX &&
          candidateSpanX <= widget.maxSpanX &&
          candidateSlot >= 0 &&
          candidateSlot ~/ widget.gridColumns ==
              nextSlot ~/ widget.gridColumns) {
        nextSlot = candidateSlot;
        nextSpanX = candidateSpanX;
      }
    }

    if (direction.affectsRight && dxSteps != 0) {
      nextSpanX = (nextSpanX + dxSteps).clamp(widget.minSpanX, widget.maxSpanX);
    }

    if (direction.affectsTop && dySteps != 0) {
      final candidateSlot = nextSlot + dySteps * widget.gridColumns;
      final candidateSpanY = nextSpanY - dySteps;
      if (candidateSpanY >= widget.minSpanY &&
          candidateSpanY <= widget.maxSpanY &&
          candidateSlot >= 0) {
        nextSlot = candidateSlot;
        nextSpanY = candidateSpanY;
      }
    }

    if (direction.affectsBottom && dySteps != 0) {
      nextSpanY = (nextSpanY + dySteps).clamp(widget.minSpanY, widget.maxSpanY);
    }

    if (nextSlot != widget.slot ||
        nextSpanX != widget.spanX ||
        nextSpanY != widget.spanY) {
      widget.onResize(nextSlot, nextSpanX, nextSpanY);
    }
  }
}

enum _ResizeDirection {
  left,
  top,
  right,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight;

  bool get affectsLeft => this == left || this == topLeft || this == bottomLeft;
  bool get affectsTop => this == top || this == topLeft || this == topRight;
  bool get affectsRight =>
      this == right || this == topRight || this == bottomRight;
  bool get affectsBottom =>
      this == bottom || this == bottomLeft || this == bottomRight;

  SystemMouseCursor get cursor => switch (this) {
        left || right => SystemMouseCursors.resizeLeftRight,
        top || bottom => SystemMouseCursors.resizeUpDown,
        topLeft || bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
        topRight || bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
      };

  Alignment get alignment => switch (this) {
        left => Alignment.centerLeft,
        top => Alignment.topCenter,
        right => Alignment.centerRight,
        bottom => Alignment.bottomCenter,
        topLeft => Alignment.topLeft,
        topRight => Alignment.topRight,
        bottomLeft => Alignment.bottomLeft,
        bottomRight => Alignment.bottomRight,
      };

  double? get leftInset => switch (this) {
        left || topLeft || bottomLeft => 0,
        _ => null,
      };

  double? get rightInset => switch (this) {
        right || topRight || bottomRight => 0,
        _ => null,
      };

  double? get topInset => switch (this) {
        top || topLeft || topRight => 0,
        _ => null,
      };

  double? get bottomInset => switch (this) {
        bottom || bottomLeft || bottomRight => 0,
        _ => null,
      };

  double? get handleWidth => switch (this) {
        left || right => _HomeWidgetStackViewState._handleSize,
        top || bottom => null,
        _ => _HomeWidgetStackViewState._handleSize,
      };

  double? get handleHeight => switch (this) {
        top || bottom => _HomeWidgetStackViewState._handleSize,
        left || right => null,
        _ => _HomeWidgetStackViewState._handleSize,
      };
}

class _WidgetResizeHandle extends StatefulWidget {
  final SystemMouseCursor cursor;
  final Alignment alignment;
  final double stepX;
  final double stepY;
  final void Function(int dxSteps, int dySteps) onDrag;

  const _WidgetResizeHandle({
    required this.cursor,
    required this.alignment,
    required this.stepX,
    required this.stepY,
    required this.onDrag,
  });

  @override
  State<_WidgetResizeHandle> createState() => _WidgetResizeHandleState();
}

class _WidgetResizeHandleState extends State<_WidgetResizeHandle> {
  double _dx = 0;
  double _dy = 0;
  bool _hasDragged = false;

  @override
  Widget build(BuildContext context) {
    final stepX = widget.stepX.clamp(24, double.infinity).toDouble();
    final stepY = widget.stepY.clamp(24, double.infinity).toDouble();
    return MouseRegion(
      cursor: widget.cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          _dx = 0;
          _dy = 0;
          _hasDragged = false;
        },
        onPanUpdate: (details) {
          _dx += details.delta.dx;
          _dy += details.delta.dy;
          _emitResizeSteps(stepX, stepY, useSnapThreshold: false);
        },
        onPanEnd: (_) => _emitResizeSteps(stepX, stepY, useSnapThreshold: true),
        onPanCancel: () =>
            _emitResizeSteps(stepX, stepY, useSnapThreshold: true),
        child: Align(
          alignment: widget.alignment,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _emitResizeSteps(
    double stepX,
    double stepY, {
    required bool useSnapThreshold,
  }) {
    final dxSteps = _stepsForDelta(_dx, stepX, useSnapThreshold);
    final dySteps = _stepsForDelta(_dy, stepY, useSnapThreshold);
    if (dxSteps == 0 && dySteps == 0) return;

    _hasDragged = true;
    _dx -= dxSteps * stepX;
    _dy -= dySteps * stepY;
    widget.onDrag(dxSteps, dySteps);
  }

  int _stepsForDelta(double delta, double step, bool useSnapThreshold) {
    if (step <= 0) return 0;
    if (!useSnapThreshold) return (delta / step).truncate();
    if (!_hasDragged && delta.abs() < step * 0.22) return 0;
    return (delta / step).round();
  }
}

class _WidgetStackItem extends StatelessWidget {
  final int appWidgetId;
  const _WidgetStackItem({required this.appWidgetId});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return _MeasuredStackWidgetView(
          appWidgetId: appWidgetId,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
        );
      },
    );
  }
}

class _MeasuredStackWidgetView extends StatefulWidget {
  final int appWidgetId;
  final double width;
  final double height;

  const _MeasuredStackWidgetView({
    required this.appWidgetId,
    required this.width,
    required this.height,
  });

  @override
  State<_MeasuredStackWidgetView> createState() =>
      _MeasuredStackWidgetViewState();
}

class _MeasuredStackWidgetViewState extends State<_MeasuredStackWidgetView> {
  int? _lastWidth;
  int? _lastHeight;

  @override
  void initState() {
    super.initState();
    _scheduleSizeSync();
  }

  @override
  void didUpdateWidget(covariant _MeasuredStackWidgetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleSizeSync();
  }

  void _scheduleSizeSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final width = widget.width.round();
      final height = widget.height.round();
      if (width <= 0 || height <= 0) return;
      if (_lastWidth == width && _lastHeight == height) return;

      _lastWidth = width;
      _lastHeight = height;
      LauncherService.updateWidgetSize(widget.appWidgetId, width, height);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'com.genrevibes.smartlauncher/widget_host_view',
      creationParams: {'appWidgetId': widget.appWidgetId},
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (_) => _scheduleSizeSync(),
    );
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int current;

  const _PageDots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: i == current ? 8 : 5,
          height: 5,
          decoration: BoxDecoration(
            color: i == current
                ? Colors.white.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
