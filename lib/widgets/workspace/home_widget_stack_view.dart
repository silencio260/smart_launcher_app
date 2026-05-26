import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/launcher_widget_info.dart';
import '../../services/launcher_service.dart';
import '../../utils/drawer_perf.dart';
import '../edit_mode/edit_mode_scope.dart';
import 'route_coverage_scope.dart';

/// Shows a swipeable stack of widgets. Long-press dragging is handled by the
/// parent CellLayoutView (same as single widgets). Resize handles work on the
/// stack as a whole.
class HomeWidgetStackView extends StatefulWidget {
  final List<LauncherWidgetInfo> widgets;
  final int spanX;
  final int spanY;
  final int page;
  final int slot;
  final int currentIndex;
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
  final ValueChanged<int>? onIndexChanged;
  final void Function(int slot, int spanX, int spanY) onResize;

  const HomeWidgetStackView({
    super.key,
    required this.widgets,
    required this.spanX,
    required this.spanY,
    required this.page,
    required this.slot,
    required this.currentIndex,
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
    this.onIndexChanged,
    required this.onResize,
  });

  /// (page, slot) of a stack whose AndroidView should be suppressed while the
  /// stack-edit overlay is mounted. The overlay renders its own AndroidViews
  /// for the same appWidgetIds, so the home rendering must release them first.
  static final ValueNotifier<(int, int)?> suppressedAt =
      ValueNotifier<(int, int)?>(null);

  @override
  State<HomeWidgetStackView> createState() => _HomeWidgetStackViewState();
}

class _HomeWidgetStackViewState extends State<HomeWidgetStackView> {
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = _safeIndex(widget.currentIndex);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void didUpdateWidget(HomeWidgetStackView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIndex = _safeIndex(widget.currentIndex);
    if (nextIndex == _currentIndex) return;
    _currentIndex = nextIndex;
    if (_pageController.hasClients) {
      _pageController.jumpToPage(nextIndex);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<(int, int)?>(
      valueListenable: HomeWidgetStackView.suppressedAt,
      builder: (context, suppressed, _) {
        if (suppressed != null &&
            suppressed.$1 == widget.page &&
            suppressed.$2 == widget.slot) {
          return const SizedBox.shrink();
        }
        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            Positioned.fill(
              // AbsorbPointer (not IgnorePointer): same reason as
              // HomeWidgetSlot — keeps the subtree hit-testable so the parent
              // LongPressDraggable can re-arm a move drag on long-press,
              // while blocking events from reaching the inner
              // PageView/AndroidViews.
              child: AbsorbPointer(
                absorbing: widget.isSelected,
                child: PageView.builder(
                  controller: _pageController,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: (i) {
                    setState(() => _currentIndex = i);
                    widget.onIndexChanged?.call(i);
                  },
                  itemCount: widget.widgets.length,
                  itemBuilder: (_, i) {
                    final w = widget.widgets[i];
                    return _WidgetStackItem(
                      key: ValueKey('stack-widget-${w.appWidgetId}'),
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
      },
    );
  }

  int _safeIndex(int index) {
    if (widget.widgets.isEmpty) return 0;
    return index.clamp(0, widget.widgets.length - 1).toInt();
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
    super.key,
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

/// Renders a single widget host view at a fixed (spanX, spanY) — used by the
/// stack-edit overlay to show every widget in a stack side-by-side. Unlike
/// the in-stack view, it does NOT honor [EditModeScope] or [RouteCoverageScope]
/// because the overlay route itself sits above those scopes.
class StackWidgetTile extends StatefulWidget {
  final LauncherWidgetInfo widgetInfo;
  final int stackSpanX;
  final int stackSpanY;
  final int gridColumns;
  final int gridRows;
  final double cellWidth;
  final double cellHeight;
  final double gap;

  const StackWidgetTile({
    super.key,
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
  State<StackWidgetTile> createState() => _StackWidgetTileState();
}

class _StackWidgetTileState extends State<StackWidgetTile> {
  String? _lastSizeKey;

  @override
  void initState() {
    super.initState();
    _scheduleSizeSync();
  }

  @override
  void didUpdateWidget(covariant StackWidgetTile oldWidget) {
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
    return RepaintBoundary(
      child: AndroidView(
        key: ValueKey('stack-edit-${widget.widgetInfo.appWidgetId}'),
        viewType: 'com.genrevibes.smartlauncher/widget_host_view',
        creationParams: {'appWidgetId': widget.widgetInfo.appWidgetId},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (_) => _scheduleSizeSync(),
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      ),
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
    DrawerPerf.event('stackSlot.mount',
        extra: {'appWidgetId': widget.widgetInfo.appWidgetId});
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
    if (EditModeScope.isActive(context)) {
      return const SizedBox.shrink();
    }
    if (RouteCoverageScope.isCovered(context)) {
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
        onPlatformViewCreated: (_) {
          DrawerPerf.event('stackSlot.platformViewCreated',
              extra: {'appWidgetId': widget.widgetInfo.appWidgetId});
          _scheduleSizeSync();
        },
        // Empty set: the platform view only receives the pointer sequence
        // when no Flutter recognizer in the arena claimed it (taps).
        // Horizontal drags flow to the nearest PageView (the stack's own
        // pager, or the workspace pager), and vertical drags flow to the
        // workspace listener.
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
