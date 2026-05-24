import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../models/launcher_settings.dart';
import '../../services/drag/drag_controller.dart';
import '../../services/gestures/widget_resize_gesture_guard.dart';
import '../../state/workspace_cubit.dart';
import 'cell_layout.dart';

class WorkspaceView extends StatefulWidget {
  final LauncherSettings settings;
  final DragController dragController;
  final void Function(AppInfo app) onAppTap;
  final void Function(AppInfo app, int page, int slot, Offset iconCenter)
      onAppLongPress;
  final VoidCallback onBackgroundLongPress;
  final void Function(double offset) onPageChanged;
  final void Function(PageController)? onControllerReady;
  final void Function(int page, int slot)? onPickWidgetForStack;

  const WorkspaceView({
    super.key,
    required this.settings,
    required this.dragController,
    required this.onAppTap,
    required this.onAppLongPress,
    required this.onBackgroundLongPress,
    required this.onPageChanged,
    this.onControllerReady,
    this.onPickWidgetForStack,
  });

  @override
  State<WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<WorkspaceView> {
  // Wallpaper-offset MethodChannel calls are coalesced to ~30Hz: the call
  // hops the UI<->platform boundary, and at 120Hz scrolling it was the
  // dominant source of jank during page swipes.
  static const Duration _kOffsetThrottle = Duration(milliseconds: 33);

  late PageController _controller;
  DateTime _lastOffsetSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  double _lastOffsetSent = -1;
  double _pendingOffset = 0;
  Timer? _trailingOffsetTimer;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onControllerReady?.call(_controller);
    });
  }

  @override
  void dispose() {
    _trailingOffsetTimer?.cancel();
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pages = context.read<WorkspaceCubit>().state.pages.length;
    if (!_controller.hasClients || pages == 0) return;
    final page = _controller.page ?? 0;
    _pendingOffset = pages > 1 ? page / (pages - 1) : 0.0;
    final now = DateTime.now();
    if (now.difference(_lastOffsetSentAt) >= _kOffsetThrottle) {
      _flushOffset(now);
    } else {
      _trailingOffsetTimer ??= Timer(_kOffsetThrottle, () {
        _trailingOffsetTimer = null;
        if (!mounted) return;
        _flushOffset(DateTime.now());
      });
    }
  }

  void _flushOffset(DateTime now) {
    if ((_pendingOffset - _lastOffsetSent).abs() < 0.001) return;
    _lastOffsetSent = _pendingOffset;
    _lastOffsetSentAt = now;
    widget.onPageChanged(_pendingOffset);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      buildWhen: (prev, curr) => prev.pages != curr.pages,
      builder: (context, state) {
        if (state.pages.isEmpty) {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<bool>(
          valueListenable: WidgetResizeGestureGuard.isResizingNotifier,
          builder: (context, isResizing, _) {
            return PageView.builder(
              controller: _controller,
              // Keeps adjacent pages alive across swipes so their AndroidView
              // widget hosts don't tear down/re-attach on every page change.
              allowImplicitScrolling: true,
              physics: isResizing
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              onPageChanged: (i) =>
                  context.read<WorkspaceCubit>().setCurrentPage(
                        i % state.pages.length,
                      ),
              itemCount:
                  widget.settings.infiniteScrolling ? null : state.pages.length,
              itemBuilder: (context, rawIndex) {
                final i = rawIndex % state.pages.length;
                return CellLayoutView(
                  page: state.pages[i],
                  pageIndex: i,
                  settings: widget.settings,
                  dragController: widget.dragController,
                  onAppTap: widget.onAppTap,
                  onAppLongPress: (app, slot, center) =>
                      widget.onAppLongPress(app, i, slot, center),
                  onBackgroundLongPress: widget.onBackgroundLongPress,
                  onPickWidgetForStack: widget.onPickWidgetForStack,
                );
              },
            );
          },
        );
      },
    );
  }
}
