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
  final double resizeStepX;
  final double resizeStepY;
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
    required this.resizeStepX,
    required this.resizeStepY,
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
        Positioned.fill(child: _WidgetView(widgetInfo: w)),
      ],
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
