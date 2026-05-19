import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/launcher_widget_info.dart';
import '../../services/launcher_service.dart';
import '../../state/workspace_cubit.dart';
import '../clock_widget.dart';
import '../edit_mode/edit_mode_scope.dart';

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
          // AbsorbPointer (not IgnorePointer): while selected, we still want
          // the parent LongPressDraggable to receive pointer events so a
          // long-press on the widget body re-arms the move drag. IgnorePointer
          // makes the subtree invisible to hit-testing, which would block the
          // ancestor Listener (deferToChild) from ever firing. AbsorbPointer
          // keeps the subtree hit-testable but stops events from reaching the
          // AndroidView underneath.
          child: AbsorbPointer(
            absorbing: widget.isSelected,
            child: _WidgetView(
              widgetInfo: w,
              gridColumns: widget.gridColumns,
              gridRows: widget.gridRows,
              cellWidth: widget.resizeStepX - widget.gridGap,
              cellHeight: widget.resizeStepY - widget.gridGap,
              gap: widget.gridGap,
            ),
          ),
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

  const _WidgetView({
    required this.widgetInfo,
    required this.gridColumns,
    required this.gridRows,
    required this.cellWidth,
    required this.cellHeight,
    required this.gap,
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
    // exceeding its ImageReader buffer budget — Visibility(maintainState:
    // true) hides this slot but keeps its host view producing frames into a
    // queue Flutter has stopped draining, which is exactly the "Unable to
    // acquire a buffer item" warning. Yielding ownership to the overlay keeps
    // one host view per id at any moment; the discrete enter/exit-edit
    // transition only disposes/recreates once each, not continuously.
    if (EditModeScope.isActive(context)) {
      return const SizedBox.shrink();
    }
    return _SpanSyncedWidgetHostView(
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
        onPlatformViewCreated: (_) => _scheduleSizeSync(),
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
