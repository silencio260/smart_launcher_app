import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/launcher_widget_info.dart';
import '../../state/workspace_cubit.dart';

/// Shows a swipeable stack of widgets. Long-press dragging is handled by the
/// parent CellLayoutView (same as single widgets). Resize handles work on the
/// stack as a whole.
class HomeWidgetStackView extends StatefulWidget {
  final List<LauncherWidgetInfo> widgets;
  final int spanX;
  final int spanY;
  final int page;
  final int slot;

  const HomeWidgetStackView({
    super.key,
    required this.widgets,
    required this.spanX,
    required this.spanY,
    required this.page,
    required this.slot,
  });

  @override
  State<HomeWidgetStackView> createState() => _HomeWidgetStackViewState();
}

class _HomeWidgetStackViewState extends State<HomeWidgetStackView> {
  late PageController _pageController;
  int _currentIndex = 0;
  static const double _handleSize = 18;

  double _dragAccumX = 0;
  double _dragAccumY = 0;

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
        // Right resize handle
        _buildRightHandle(context),
        // Bottom resize handle
        _buildBottomHandle(context),
        const Positioned(
          right: 2,
          bottom: 2,
          child: Icon(Icons.open_in_full, color: Colors.white38, size: 12),
        ),
      ],
    );
  }

  Widget _buildRightHandle(BuildContext context) {
    return Positioned(
      right: 0,
      top: 0,
      bottom: _handleSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _dragAccumX = 0,
        onHorizontalDragUpdate: (d) {
          _dragAccumX += d.delta.dx;
          final steps = (_dragAccumX / 60).truncate();
          if (steps != 0) {
            _dragAccumX -= steps * 60;
            final newSpan = (widget.spanX + steps).clamp(1, 4);
            if (newSpan != widget.spanX) {
              context
                  .read<WorkspaceCubit>()
                  .updateWidgetStackSpan(widget.page, widget.slot, newSpan, widget.spanY);
            }
          }
        },
        child: Container(
          width: _handleSize,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: const BorderRadius.only(topRight: Radius.circular(8)),
          ),
          child: const Center(
            child: Icon(Icons.drag_indicator, color: Colors.white38, size: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomHandle(BuildContext context) {
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
            final newSpan = (widget.spanY + steps).clamp(1, 4);
            if (newSpan != widget.spanY) {
              context
                  .read<WorkspaceCubit>()
                  .updateWidgetStackSpan(widget.page, widget.slot, widget.spanX, newSpan);
            }
          }
        },
        child: Container(
          height: _handleSize,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8)),
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

class _WidgetStackItem extends StatelessWidget {
  final int appWidgetId;
  const _WidgetStackItem({required this.appWidgetId});

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
