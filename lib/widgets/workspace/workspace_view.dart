import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../models/launcher_settings.dart';
import '../../services/drag/drag_controller.dart';
import '../../services/gestures/widget_resize_gesture_guard.dart';
import '../../state/workspace_cubit.dart';
import '../../utils/debug_flags.dart';
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
  static const double _gridGap = 8;
  static const double _horizontalPadding = 16;
  static const double _verticalPadding = 8;

  late PageController _controller;
  final GlobalKey _pageViewKey = GlobalKey();
  DateTime _lastOffsetSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  double _lastOffsetSent = -1;
  double _pendingOffset = 0;
  Timer? _trailingOffsetTimer;
  WorkspaceState? _lastWorkspaceState;

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

  ({int page, int slot})? _resolveDropLocation(
    Offset globalPosition,
    WorkspaceState state,
  ) {
    if (state.pages.isEmpty) {
      dragDropLog(
          '[WidgetDragDrop][workspace] resolveDropLocation abort=noPages');
      return null;
    }
    final box = _pageViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) {
      dragDropLog(
        '[WidgetDragDrop][workspace] resolveDropLocation abort=noAttachedBox',
      );
      return null;
    }

    final rawPage = _controller.hasClients
        ? _controller.page ?? _controller.initialPage.toDouble()
        : state.currentPage.toDouble();
    final roundedRawPage = rawPage.round();
    final page = widget.settings.infiniteScrolling
        ? roundedRawPage % state.pages.length
        : roundedRawPage.clamp(0, state.pages.length - 1).toInt();
    final local = box.globalToLocal(globalPosition);
    final gridWidth = box.size.width - _horizontalPadding * 2;
    final gridHeight = box.size.height - _verticalPadding * 2;
    if (gridWidth <= 0 || gridHeight <= 0) {
      dragDropLog(
        '[WidgetDragDrop][workspace] resolveDropLocation abort=badGrid '
        'grid=${gridWidth.toStringAsFixed(1)}x${gridHeight.toStringAsFixed(1)}',
      );
      return null;
    }

    final columns = widget.settings.gridColumns;
    final rows = widget.settings.gridRows;
    final cellWidth = (gridWidth - (columns - 1) * _gridGap) / columns;
    final cellHeight = (gridHeight - (rows - 1) * _gridGap) / rows;
    if (cellWidth <= 0 || cellHeight <= 0) {
      dragDropLog(
        '[WidgetDragDrop][workspace] resolveDropLocation abort=badCell '
        'cell=${cellWidth.toStringAsFixed(1)}x${cellHeight.toStringAsFixed(1)}',
      );
      return null;
    }

    final gridX = (local.dx - _horizontalPadding).clamp(0.0, gridWidth);
    final gridY = (local.dy - _verticalPadding).clamp(0.0, gridHeight);
    final col =
        (gridX / (cellWidth + _gridGap)).floor().clamp(0, columns - 1).toInt();
    final row =
        (gridY / (cellHeight + _gridGap)).floor().clamp(0, rows - 1).toInt();
    dragDropLog(
      '[WidgetDragDrop][workspace] resolveDropLocation '
      'global=$globalPosition local=$local rawPage=${rawPage.toStringAsFixed(3)} '
      'statePage=${state.currentPage} resolved=$page:${row * columns + col} '
      'grid=${gridWidth.toStringAsFixed(1)}x${gridHeight.toStringAsFixed(1)} '
      'cell=${cellWidth.toStringAsFixed(1)}x${cellHeight.toStringAsFixed(1)}',
    );
    return (page: page, slot: row * columns + col);
  }

  void _syncControllerToWorkspacePage(
    WorkspaceState previous,
    WorkspaceState current,
  ) {
    if (!_controller.hasClients || current.pages.isEmpty) return;

    final pageCountChanged = previous.pages.length != current.pages.length;
    final currentPageChanged = previous.currentPage != current.currentPage;
    if (!pageCountChanged && !currentPageChanged) return;

    final isOnlyDragContentUpdate = widget.dragController.isDragging &&
        previous.pages.length == current.pages.length &&
        previous.currentPage == current.currentPage;
    if (isOnlyDragContentUpdate) return;

    final pagesWereAddedDuringDrag = widget.dragController.isDragging &&
        current.pages.length > previous.pages.length;
    if (pagesWereAddedDuringDrag) return;

    final targetPage =
        current.currentPage.clamp(0, current.pages.length - 1).toInt();
    final rawPage = _controller.page ?? _controller.initialPage.toDouble();
    final roundedPage = rawPage.round();
    final controllerOutOfRange = !widget.settings.infiniteScrolling &&
        roundedPage >= current.pages.length;
    if (!controllerOutOfRange && roundedPage == targetPage) return;

    dragDropLog(
      '[WidgetDragDrop][workspace] syncPageController '
      'rawPage=${rawPage.toStringAsFixed(3)} target=$targetPage '
      'pages=${previous.pages.length}->${current.pages.length} '
      'statePage=${previous.currentPage}->${current.currentPage}',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients || current.pages.isEmpty) return;
      final safeTarget =
          current.currentPage.clamp(0, current.pages.length - 1).toInt();
      _controller.jumpToPage(safeTarget);
      _pendingOffset = current.pages.length > 1
          ? safeTarget / (current.pages.length - 1)
          : 0;
      _flushOffset(DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WorkspaceCubit, WorkspaceState>(
      listenWhen: (prev, curr) =>
          prev.pages != curr.pages || prev.currentPage != curr.currentPage,
      listener: (context, state) {
        final previous = _lastWorkspaceState ?? state;
        _syncControllerToWorkspacePage(previous, state);
        _lastWorkspaceState = state;
      },
      buildWhen: (prev, curr) => prev.pages != curr.pages,
      builder: (context, state) {
        _lastWorkspaceState ??= state;
        if (state.pages.isEmpty) {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<bool>(
          valueListenable: WidgetResizeGestureGuard.isResizingNotifier,
          builder: (context, isResizing, _) {
            return PageView.builder(
              key: _pageViewKey,
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
                  resolveDropLocation: (globalPosition) =>
                      _resolveDropLocation(globalPosition, state),
                );
              },
            );
          },
        );
      },
    );
  }
}
