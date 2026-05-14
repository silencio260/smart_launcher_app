import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/launcher_widget_info.dart';
import '../../services/launcher_service.dart';
import '../../state/workspace_cubit.dart';
import '../clock_widget.dart';

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
          child: IgnorePointer(
            ignoring: widget.isSelected,
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

  void _scheduleSizeSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.widgetInfo.spanX <= 0 || widget.widgetInfo.spanY <= 0) return;
      final sizeKey = [
        widget.widgetInfo.appWidgetId,
        widget.widgetInfo.spanX,
        widget.widgetInfo.spanY,
        widget.gridColumns,
        widget.gridRows,
        widget.cellWidth.round(),
        widget.cellHeight.round(),
        widget.gap.round(),
      ].join(':');
      if (_lastSizeKey == sizeKey) return;

      _lastSizeKey = sizeKey;
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
    return AndroidView(
      key: ValueKey(widget.widgetInfo.appWidgetId),
      viewType: 'com.genrevibes.smartlauncher/widget_host_view',
      creationParams: {'appWidgetId': widget.widgetInfo.appWidgetId},
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (_) => _scheduleSizeSync(),
    );
  }
}
