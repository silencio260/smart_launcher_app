import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/launcher_widget_info.dart';
import '../../state/workspace_cubit.dart';

/// Renders a single Android app widget with resize handles on the right and
/// bottom edges. The LongPressDraggable for moving is owned by CellLayoutView,
/// so this widget only handles resizing.
class HomeWidgetSlot extends StatefulWidget {
  final LauncherWidgetInfo widget;
  final int page;
  final int slot;

  const HomeWidgetSlot({
    super.key,
    required this.widget,
    required this.page,
    required this.slot,
  });

  @override
  State<HomeWidgetSlot> createState() => _HomeWidgetSlotState();
}

class _HomeWidgetSlotState extends State<HomeWidgetSlot> {
  static const double _handleSize = 18;

  // Accumulated drag delta for smooth resize
  double _dragAccumX = 0;
  double _dragAccumY = 0;

  @override
  Widget build(BuildContext context) {
    final w = widget.widget;
    return Stack(
      children: [
        Positioned.fill(child: _WidgetView(appWidgetId: w.appWidgetId)),
        _buildRightHandle(context, w),
        _buildBottomHandle(context, w),
        // Corner indicator (visual affordance, no interaction)
        const Positioned(
          right: 2,
          bottom: 2,
          child: Icon(Icons.open_in_full, color: Colors.white38, size: 12),
        ),
      ],
    );
  }

  Widget _buildRightHandle(BuildContext context, LauncherWidgetInfo w) {
    return Positioned(
      right: 0,
      top: 0,
      bottom: _handleSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _dragAccumX = 0,
        onHorizontalDragUpdate: (d) {
          _dragAccumX += d.delta.dx;
          // Each ~60px of drag = one column step
          final steps = (_dragAccumX / 60).truncate();
          if (steps != 0) {
            _dragAccumX -= steps * 60;
            final newSpan = (w.spanX + steps).clamp(1, 4);
            if (newSpan != w.spanX) {
              context
                  .read<WorkspaceCubit>()
                  .updateWidgetSpan(widget.page, widget.slot, w.copyWith(spanX: newSpan));
            }
          }
        },
        child: Container(
          width: _handleSize,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(8),
            ),
          ),
          child: const Center(
            child: Icon(Icons.drag_indicator, color: Colors.white38, size: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomHandle(BuildContext context, LauncherWidgetInfo w) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: _handleSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => _dragAccumY = 0,
        onVerticalDragUpdate: (d) {
          _dragAccumY += d.delta.dy;
          final steps = (_dragAccumY / 60).truncate();
          if (steps != 0) {
            _dragAccumY -= steps * 60;
            final newSpan = (w.spanY + steps).clamp(1, 4);
            if (newSpan != w.spanY) {
              context
                  .read<WorkspaceCubit>()
                  .updateWidgetSpan(widget.page, widget.slot, w.copyWith(spanY: newSpan));
            }
          }
        },
        child: Container(
          height: _handleSize,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(8),
            ),
          ),
          child: const Center(
            child: RotatedBox(
              quarterTurns: 1,
              child: Icon(Icons.drag_indicator, color: Colors.white38, size: 14),
            ),
          ),
        ),
      ),
    );
  }
}

class _WidgetView extends StatelessWidget {
  final int appWidgetId;

  const _WidgetView({required this.appWidgetId});

  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'com.genrevibes.smartlauncher/widget_host_view',
      creationParams: {'appWidgetId': appWidgetId},
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (_) {},
    );
  }
}
