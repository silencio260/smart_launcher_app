import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/launcher_widget_info.dart';
import '../../services/launcher_service.dart';
import '../../state/workspace_cubit.dart';
import '../clock_widget.dart';
import '../../utils/drawer_perf.dart';
import '../edit_mode/edit_mode_scope.dart';
import 'route_coverage_scope.dart';

/// Renders a single Android app widget with resize handles. The
/// LongPressDraggable for moving is owned by CellLayoutView, so this widget
/// only handles resizing.
class HomeWidgetSlot extends StatefulWidget {
  final LauncherWidgetInfo widget;
  final int page;
  final int slot;
  final int minSpanX;
  final int minSpanY;
  final int maxSpanX;
  final int maxSpanY;
  final int gridColumns;
  final int gridRows;
  final double resizeStepX;
  final double resizeStepY;
  final double gridGap;
  final bool isSelected;
  final VoidCallback onDismissResize;
  final void Function(int slot, int spanX, int spanY) onResize;
  // DIAGNOSTIC: when supplied (a GlobalKey shared between the resting child and
  // childWhenDragging), the live AppWidgetHostView migrates across the drag
  // swap instead of being torn down and re-attached. See _hostViewKeyFor in
  // cell_layout.dart.
  final Key? hostViewKey;

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
    required this.gridRows,
    required this.resizeStepX,
    required this.resizeStepY,
    required this.gridGap,
    required this.isSelected,
    required this.onDismissResize,
    required this.onResize,
    this.hostViewKey,
  });

  @override
  State<HomeWidgetSlot> createState() => _HomeWidgetSlotState();
}

class _HomeWidgetSlotState extends State<HomeWidgetSlot> {
  @override
  Widget build(BuildContext context) {
    final w = widget.widget;
    return Stack(
      children: [
        Positioned.fill(
          // The live AppWidgetHostView. Its ancestor chain MUST NOT change with
          // selection. Previously this was wrapped in
          // AbsorbPointer(absorbing: isSelected); under hybrid composition +
          // RenderMode.texture, flipping a pointer-suppression widget directly
          // above the AndroidView re-evaluates the platform view's overlay
          // placement and composites the host texture at a persistent
          // up-and-left offset for the whole duration of the selection -- the
          // "widget jumps and stays put on long-press" bug. Input is now
          // blocked by a sibling layer on top (below) instead, which leaves
          // this subtree's ancestors untouched so the texture never moves.
          child: _WidgetView(
            widgetInfo: w,
            gridColumns: widget.gridColumns,
            gridRows: widget.gridRows,
            cellWidth: widget.resizeStepX - widget.gridGap,
            cellHeight: widget.resizeStepY - widget.gridGap,
            gap: widget.gridGap,
            hostViewKey: widget.hostViewKey,
          ),
        ),
        // While selected, swallow taps before they reach the widget body, but
        // keep the layer hit-testable (AbsorbPointer, not IgnorePointer) so the
        // ancestor LongPressDraggable Listener (deferToChild) still fires and a
        // long-press on the body can re-arm a move drag. Placed as a SIBLING on
        // top rather than as an ancestor of the AndroidView so toggling it never
        // perturbs the platform view's placement.
        if (widget.isSelected)
          const Positioned.fill(
            child: AbsorbPointer(child: SizedBox.expand()),
          ),
      ],
    );
  }
}

class _WidgetView extends StatelessWidget {
  final LauncherWidgetInfo widgetInfo;
  final int gridColumns;
  final int gridRows;
  final double cellWidth;
  final double cellHeight;
  final double gap;
  final Key? hostViewKey;

  const _WidgetView({
    required this.widgetInfo,
    required this.gridColumns,
    required this.gridRows,
    required this.cellWidth,
    required this.cellHeight,
    required this.gap,
    this.hostViewKey,
  });

  @override
  Widget build(BuildContext context) {
    if (widgetInfo.isCustomWidget &&
        widgetInfo.providerPackage ==
            WorkspaceCubit.defaultClockProviderPackage &&
        widgetInfo.providerClass == WorkspaceCubit.defaultClockProviderClass) {
      return const Center(child: ClockWidget());
    }

    // Drop the AndroidView while edit mode is active. The edit overlay mounts
    // its own AndroidView for the same appWidgetId, and Android can't have
    // two live AppWidgetHostViews bound to the same id without one of them
    // exceeding its ImageReader buffer budget.
    if (EditModeScope.isActive(context)) {
      return const SizedBox.shrink();
    }
    // Drop the AndroidView when covered by another route. Hybrid composition
    // of a live AppWidgetHostView keeps costing per-frame work even when the
    // home screen is fully obscured, which surfaces as scroll jank on the
    // page on top. The native side pools AppWidgetHostView instances by
    // appWidgetId (see WidgetHostViewRegistry), so re-creating on uncover
    // reuses the cached host instead of re-binding to system_server.
    if (RouteCoverageScope.isCovered(context)) {
      return const SizedBox.shrink();
    }
    return _SpanSyncedWidgetHostView(
      key: hostViewKey,
      widgetInfo: widgetInfo,
      gridColumns: gridColumns,
      gridRows: gridRows,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
      gap: gap,
    );
  }
}

class _SpanSyncedWidgetHostView extends StatefulWidget {
  final LauncherWidgetInfo widgetInfo;
  final int gridColumns;
  final int gridRows;
  final double cellWidth;
  final double cellHeight;
  final double gap;

  const _SpanSyncedWidgetHostView({
    super.key,
    required this.widgetInfo,
    required this.gridColumns,
    required this.gridRows,
    required this.cellWidth,
    required this.cellHeight,
    required this.gap,
  });

  @override
  State<_SpanSyncedWidgetHostView> createState() =>
      _SpanSyncedWidgetHostViewState();
}

class _SpanSyncedWidgetHostViewState extends State<_SpanSyncedWidgetHostView> {
  String? _lastSizeKey;

  @override
  void didUpdateWidget(covariant _SpanSyncedWidgetHostView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleSizeSync();
  }

  @override
  void initState() {
    super.initState();
    DrawerPerf.event('widgetSlot.mount',
        extra: {'appWidgetId': widget.widgetInfo.appWidgetId});
    _scheduleSizeSync();
  }

  String? _computeSizeKey() {
    if (widget.widgetInfo.spanX <= 0 || widget.widgetInfo.spanY <= 0) {
      return null;
    }
    return [
      widget.widgetInfo.appWidgetId,
      widget.widgetInfo.spanX,
      widget.widgetInfo.spanY,
      widget.gridColumns,
      widget.gridRows,
      widget.cellWidth.round(),
      widget.cellHeight.round(),
      widget.gap.round(),
    ].join(':');
  }

  void _scheduleSizeSync() {
    // Dedupe BEFORE scheduling so we don't post a frame callback per build.
    final sizeKey = _computeSizeKey();
    if (sizeKey == null || _lastSizeKey == sizeKey) return;
    _lastSizeKey = sizeKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      LauncherService.updateWidgetSize(
        widget.widgetInfo.appWidgetId,
        widget.widgetInfo.providerPackage,
        widget.widgetInfo.providerClass,
        widget.widgetInfo.spanX,
        widget.widgetInfo.spanY,
        gridColumns: widget.gridColumns,
        gridRows: widget.gridRows,
        cellWidth: widget.cellWidth,
        cellHeight: widget.cellHeight,
        gap: widget.gap,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary isolates the platform view's compositor layer so
    // PageView translation during scroll doesn't invalidate its raster.
    return RepaintBoundary(
      child: AndroidView(
        key: ValueKey(widget.widgetInfo.appWidgetId),
        viewType: 'com.genrevibes.smartlauncher/widget_host_view',
        creationParams: {'appWidgetId': widget.widgetInfo.appWidgetId},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (_) {
          DrawerPerf.event('widgetSlot.platformViewCreated',
              extra: {'appWidgetId': widget.widgetInfo.appWidgetId});
          _scheduleSizeSync();
        },
        // Empty set: the platform view only receives a pointer sequence when
        // no Flutter recognizer in the arena claimed it (i.e. taps). Horizontal
        // drags go to PageView; vertical drags go to the workspace touch
        // listener. Adding drag recognizers here would route those gestures TO
        // the widget instead.
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      ),
    );
  }
}
