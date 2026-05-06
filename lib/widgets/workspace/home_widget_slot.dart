import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/launcher_widget_info.dart';
import '../../state/workspace_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
  bool _resizing = false;
  final double _resizeHandleSize = 20;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _WidgetView(appWidgetId: widget.widget.appWidgetId),
        if (_resizing) _buildResizeHandles(context),
        GestureDetector(
          onLongPress: () => setState(() => _resizing = !_resizing),
          behavior: HitTestBehavior.translucent,
          child: const SizedBox.expand(),
        ),
      ],
    );
  }

  Widget _buildResizeHandles(BuildContext context) {
    final cubit = context.read<WorkspaceCubit>();
    return Stack(
      children: [
        // Right edge — expand columns
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: GestureDetector(
            onHorizontalDragEnd: (d) {
              if (d.primaryVelocity != null && d.primaryVelocity! > 0) {
                final updated = widget.widget.copyWith(
                  spanX: (widget.widget.spanX + 1).clamp(1, 4),
                );
                cubit.updateWidgetSpan(widget.page, widget.slot, updated);
              }
              setState(() => _resizing = false);
            },
            child: Container(
              width: _resizeHandleSize,
              color: Colors.white.withValues(alpha: 0.3),
              child: const Icon(Icons.drag_handle, color: Colors.white70, size: 16),
            ),
          ),
        ),
        // Bottom edge — expand rows
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: GestureDetector(
            onVerticalDragEnd: (d) {
              if (d.primaryVelocity != null && d.primaryVelocity! > 0) {
                final updated = widget.widget.copyWith(
                  spanY: (widget.widget.spanY + 1).clamp(1, 4),
                );
                cubit.updateWidgetSpan(widget.page, widget.slot, updated);
              }
              setState(() => _resizing = false);
            },
            child: Container(
              height: _resizeHandleSize,
              color: Colors.white.withValues(alpha: 0.3),
              child: const Icon(Icons.drag_handle, color: Colors.white70, size: 16),
            ),
          ),
        ),
      ],
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
