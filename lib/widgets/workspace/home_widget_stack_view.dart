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
      ],
    );
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
