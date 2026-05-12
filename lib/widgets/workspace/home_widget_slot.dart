import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/launcher_widget_info.dart';
import '../../services/launcher_service.dart';
import '../../state/workspace_cubit.dart';
import '../clock_widget.dart';

/// Renders a single Android app widget with resize handles on the right and
/// bottom edges. The LongPressDraggable for moving is owned by CellLayoutView,
/// so this widget only handles resizing.
class HomeWidgetSlot extends StatefulWidget {
  final LauncherWidgetInfo widget;
  final int page;
  final int slot;
  final int minSpanX;
  final int minSpanY;
  final int maxSpanX;
  final int maxSpanY;
  final int gridColumns;
  final void Function(int slot, int spanX, int spanY) onResize;

  const HomeWidgetSlot({
    super.key,
    required this.widget,
    required this.page,
    required this.slot,
    required this.minSpanX,
    required this.minSpanY,
    required this.maxSpanX,
    required this.maxSpanY,
    required this.gridColumns,
    required this.onResize,
  });

  @override
  State<HomeWidgetSlot> createState() => _HomeWidgetSlotState();
}

class _HomeWidgetSlotState extends State<HomeWidgetSlot> {
  static const double _frameInset = 6;
  static const double _handleSize = 22;

  @override
  Widget build(BuildContext context) {
    final w = widget.widget;
    return Stack(
      children: [
        Positioned.fill(child: _WidgetView(widgetInfo: w)),
        // Transparent but fully hit-testable surface. Flutter's Stack
        // hit-tests children from top to bottom and stops at the first hit,
        // so this widget is found before the AndroidView below it. The
        // touch event therefore stays in Flutter's gesture arena, which
        // lets LongPressDraggable (the ancestor) recognise the long-press
        // and start a drag — something the AndroidView would otherwise
        // swallow before Flutter ever sees it.
        Positioned.fill(child: ColoredBox(color: Colors.transparent)),
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
        ..._buildResizeHandles(w),
      ],
    );
  }

  List<Widget> _buildResizeHandles(LauncherWidgetInfo widgetInfo) {
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
    return directions
        .map((direction) => _buildHandle(widgetInfo, direction))
        .toList();
  }

  Widget _buildHandle(
    LauncherWidgetInfo widgetInfo,
    _ResizeDirection direction,
  ) {
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
            size: Size(constraints.maxWidth, constraints.maxHeight),
            onDrag: (dxSteps, dySteps) => _applyResize(
              widgetInfo,
              direction,
              dxSteps,
              dySteps,
            ),
          );
        },
      ),
    );
  }

  void _applyResize(
    LauncherWidgetInfo widgetInfo,
    _ResizeDirection direction,
    int dxSteps,
    int dySteps,
  ) {
    if (dxSteps == 0 && dySteps == 0) return;

    var nextSlot = widget.slot;
    var nextSpanX = widgetInfo.spanX;
    var nextSpanY = widgetInfo.spanY;

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
        nextSpanX != widgetInfo.spanX ||
        nextSpanY != widgetInfo.spanY) {
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
        left || right => _HomeWidgetSlotState._handleSize,
        top || bottom => null,
        _ => _HomeWidgetSlotState._handleSize,
      };

  double? get handleHeight => switch (this) {
        top || bottom => _HomeWidgetSlotState._handleSize,
        left || right => null,
        _ => _HomeWidgetSlotState._handleSize,
      };
}

class _WidgetResizeHandle extends StatefulWidget {
  final SystemMouseCursor cursor;
  final Alignment alignment;
  final Size size;
  final void Function(int dxSteps, int dySteps) onDrag;

  const _WidgetResizeHandle({
    required this.cursor,
    required this.alignment,
    required this.size,
    required this.onDrag,
  });

  @override
  State<_WidgetResizeHandle> createState() => _WidgetResizeHandleState();
}

class _WidgetResizeHandleState extends State<_WidgetResizeHandle> {
  double _dx = 0;
  double _dy = 0;

  @override
  Widget build(BuildContext context) {
    final stepX = (widget.size.width.clamp(44, 120)) / 2;
    final stepY = (widget.size.height.clamp(44, 120)) / 2;
    return MouseRegion(
      cursor: widget.cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) {
          _dx = 0;
          _dy = 0;
        },
        onPanUpdate: (details) {
          _dx += details.delta.dx;
          _dy += details.delta.dy;
          final dxSteps = (_dx / stepX).truncate();
          final dySteps = (_dy / stepY).truncate();
          if (dxSteps == 0 && dySteps == 0) return;
          _dx -= dxSteps * stepX;
          _dy -= dySteps * stepY;
          widget.onDrag(dxSteps, dySteps);
        },
        child: Align(
          alignment: widget.alignment,
          child: Container(
            width: 14,
            height: 14,
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
}

class _WidgetView extends StatelessWidget {
  final LauncherWidgetInfo widgetInfo;

  const _WidgetView({required this.widgetInfo});

  @override
  Widget build(BuildContext context) {
    if (widgetInfo.isCustomWidget &&
        widgetInfo.providerPackage ==
            WorkspaceCubit.defaultClockProviderPackage &&
        widgetInfo.providerClass == WorkspaceCubit.defaultClockProviderClass) {
      return const Center(child: ClockWidget());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return _MeasuredWidgetHostView(
          appWidgetId: widgetInfo.appWidgetId,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
        );
      },
    );
  }
}

class _MeasuredWidgetHostView extends StatefulWidget {
  final int appWidgetId;
  final double width;
  final double height;

  const _MeasuredWidgetHostView({
    required this.appWidgetId,
    required this.width,
    required this.height,
  });

  @override
  State<_MeasuredWidgetHostView> createState() =>
      _MeasuredWidgetHostViewState();
}

class _MeasuredWidgetHostViewState extends State<_MeasuredWidgetHostView> {
  int? _lastWidth;
  int? _lastHeight;

  @override
  void didUpdateWidget(covariant _MeasuredWidgetHostView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleSizeSync();
  }

  @override
  void initState() {
    super.initState();
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
