import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/launcher_widget_info.dart';
import '../../services/launcher_service.dart';
import '../edit_mode/edit_mode_scope.dart';

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
  final int gridRows;
  final double resizeStepX;
  final double resizeStepY;
  final double gridGap;
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
    required this.gridRows,
    required this.resizeStepX,
    required this.resizeStepY,
    required this.gridGap,
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
          child: IgnorePointer(
            ignoring: widget.isSelected,
            child: PageView.builder(
              controller: _pageController,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemCount: widget.widgets.length,
              itemBuilder: (_, i) {
                final w = widget.widgets[i];
                return _WidgetStackItem(
                  widgetInfo: w,
                  stackSpanX: widget.spanX,
                  stackSpanY: widget.spanY,
                  gridColumns: widget.gridColumns,
                  gridRows: widget.gridRows,
                  cellWidth: widget.resizeStepX - widget.gridGap,
                  cellHeight: widget.resizeStepY - widget.gridGap,
                  gap: widget.gridGap,
                );
              },
            ),
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
      ],
    );
  }
}

class _WidgetStackItem extends StatelessWidget {
  final LauncherWidgetInfo widgetInfo;
  final int stackSpanX;
  final int stackSpanY;
  final int gridColumns;
  final int gridRows;
  final double cellWidth;
  final double cellHeight;
  final double gap;

  const _WidgetStackItem({
    required this.widgetInfo,
    required this.stackSpanX,
    required this.stackSpanY,
    required this.gridColumns,
    required this.gridRows,
    required this.cellWidth,
    required this.cellHeight,
    required this.gap,
  });

  @override
  Widget build(BuildContext context) {
    return _SpanSyncedStackWidgetView(
      widgetInfo: widgetInfo,
      stackSpanX: stackSpanX,
      stackSpanY: stackSpanY,
      gridColumns: gridColumns,
      gridRows: gridRows,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
      gap: gap,
    );
  }
}

class _SpanSyncedStackWidgetView extends StatefulWidget {
  final LauncherWidgetInfo widgetInfo;
  final int stackSpanX;
  final int stackSpanY;
  final int gridColumns;
  final int gridRows;
  final double cellWidth;
  final double cellHeight;
  final double gap;

  const _SpanSyncedStackWidgetView({
    required this.widgetInfo,
    required this.stackSpanX,
    required this.stackSpanY,
    required this.gridColumns,
    required this.gridRows,
    required this.cellWidth,
    required this.cellHeight,
    required this.gap,
  });

  @override
  State<_SpanSyncedStackWidgetView> createState() =>
      _SpanSyncedStackWidgetViewState();
}

class _SpanSyncedStackWidgetViewState
    extends State<_SpanSyncedStackWidgetView> {
  String? _lastSizeKey;

  @override
  void initState() {
    super.initState();
    _scheduleSizeSync();
  }

  @override
  void didUpdateWidget(covariant _SpanSyncedStackWidgetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleSizeSync();
  }

  String? _computeSizeKey() {
    if (widget.stackSpanX <= 0 || widget.stackSpanY <= 0) return null;
    return [
      widget.widgetInfo.appWidgetId,
      widget.stackSpanX,
      widget.stackSpanY,
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
        widget.stackSpanX,
        widget.stackSpanY,
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
    // Yield ownership to the edit overlay while edit mode is active — two
    // AppWidgetHostViews bound to the same appWidgetId overflow the hybrid-
    // composition ImageReader. See HomeWidgetSlot for the full rationale.
    if (EditModeScope.isActive(context)) {
      return const SizedBox.shrink();
    }
    // RepaintBoundary isolates the platform view's compositor layer so
    // PageView translation during scroll doesn't invalidate its raster.
    return RepaintBoundary(
      child: AndroidView(
        key: ValueKey(widget.widgetInfo.appWidgetId),
        viewType: 'com.genrevibes.smartlauncher/widget_host_view',
        creationParams: {'appWidgetId': widget.widgetInfo.appWidgetId},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (_) => _scheduleSizeSync(),
        // Empty set: the platform view only receives the pointer sequence when
        // no Flutter recognizer in the arena claimed it (taps). Horizontal
        // drags flow to the nearest PageView (the stack's own pager, or the
        // workspace pager), and vertical drags flow to the workspace listener.
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      ),
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
