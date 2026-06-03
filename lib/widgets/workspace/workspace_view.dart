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
import 'home_sections.dart';

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

  /// Builders for the flanking, non-editable special pages. When null (or the
  /// matching settings flag is off) that side has no special page and the pager
  /// behaves exactly as before. The Discover page sits left of home page 0; the
  /// App Library sits right of the last home page.
  final WidgetBuilder? discoverBuilder;
  final WidgetBuilder? libraryBuilder;

  /// Insets reserved on HOME pages only: [homeTopInset] for the status bar and
  /// [homeBottomInset] for the dock + Smart-search pill band (which is drawn as
  /// a separate overlay by the host). Special pages ignore these and fill the
  /// whole pager cell. Drag-drop geometry subtracts the same insets so resolved
  /// slots match the padded home grid exactly.
  final double homeTopInset;
  final double homeBottomInset;

  /// Fired when the pager settles on a section (home / discover / library).
  final ValueChanged<HomeSection>? onSectionSettled;

  /// Fired continuously during scroll with the dock/pill "chrome" opacity
  /// (1.0 across the home band, ramping to 0.0 into a special page). Writes to a
  /// ValueNotifier in the host — does NOT rebuild the pager subtree.
  final ValueChanged<double>? onChromeProgress;

  /// Fired continuously with the dock/pill chrome horizontal slide fraction
  /// (-1..1) so the host can translate the chrome off-screen in step with the
  /// page swipe instead of having it dissolve in place.
  final ValueChanged<double>? onChromeSlide;

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
    this.discoverBuilder,
    this.libraryBuilder,
    this.homeTopInset = 0,
    this.homeBottomInset = 0,
    this.onSectionSettled,
    this.onChromeProgress,
    this.onChromeSlide,
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

  int get _leadingCount =>
      (widget.settings.discoverPageEnabled && widget.discoverBuilder != null)
          ? 1
          : 0;
  int get _trailingCount =>
      (widget.settings.appLibraryPageEnabled && widget.libraryBuilder != null)
          ? 1
          : 0;

  PagerLayout _layoutFor(WorkspaceState state) => PagerLayout(
        leadingCount: _leadingCount,
        trailingCount: _trailingCount,
        homeCount: state.pages.length,
      );

  // Infinite scrolling is incompatible with fixed flanking pages — a wrap-around
  // pager has no edges to anchor the specials to.
  bool get _effectiveInfinite =>
      widget.settings.infiniteScrolling && _leadingCount + _trailingCount == 0;

  @override
  void initState() {
    super.initState();
    // Open on the first HOME page, not on the Discover page (index 0).
    _controller = PageController(initialPage: _leadingCount);
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onControllerReady?.call(_controller);
    });
  }

  @override
  void didUpdateWidget(WorkspaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the user toggles the Discover page on/off the leading offset shifts, so
    // re-pin the controller onto the current home page to keep it from sliding.
    final oldLeading =
        (oldWidget.settings.discoverPageEnabled && oldWidget.discoverBuilder != null)
            ? 1
            : 0;
    if (oldLeading != _leadingCount && _controller.hasClients) {
      final state = context.read<WorkspaceCubit>().state;
      if (state.pages.isNotEmpty) {
        final target = _leadingCount +
            state.currentPage.clamp(0, state.pages.length - 1).toInt();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _controller.hasClients) _controller.jumpToPage(target);
        });
      }
    }
  }

  @override
  void dispose() {
    _trailingOffsetTimer?.cancel();
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    final state = context.read<WorkspaceCubit>().state;
    final pages = state.pages.length;
    if (!_controller.hasClients || pages == 0) return;
    final layout = _layoutFor(state);
    final raw = _controller.page ?? 0;

    // Dock/pill chrome opacity + slide — smooth, every frame, no pager rebuild.
    widget.onChromeProgress?.call(layout.chromeOpacityFor(raw));
    widget.onChromeSlide?.call(layout.chromeSlideFor(raw));

    // Wallpaper offset — computed over the home band only so parallax freezes at
    // the edge while swiping into a special page.
    if (layout.hasSpecials) {
      final homePos =
          (raw - layout.leadingCount).clamp(0.0, (pages - 1).toDouble());
      _pendingOffset = pages > 1 ? homePos / (pages - 1) : 0.0;
    } else {
      _pendingOffset = pages > 1 ? raw / (pages - 1) : 0.0;
    }

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

    final layout = _layoutFor(state);
    final rawPage = _controller.hasClients
        ? _controller.page ?? _controller.initialPage.toDouble()
        : state.currentPage.toDouble();
    final roundedRawPage = rawPage.round();
    // A drag that drifts onto a special page resolves onto the nearest real
    // home page — specials are never drop targets.
    final page = layout.hasSpecials
        ? layout.homeIndexFor(roundedRawPage)
        : (_effectiveInfinite
            ? roundedRawPage % state.pages.length
            : roundedRawPage.clamp(0, state.pages.length - 1).toInt());
    final local = box.globalToLocal(globalPosition);
    // Home pages are padded by homeTopInset/homeBottomInset inside the pager
    // cell; subtract them so the grid we measure against matches CellLayoutView.
    final gridWidth = box.size.width - _horizontalPadding * 2;
    final gridHeight = box.size.height -
        widget.homeTopInset -
        widget.homeBottomInset -
        _verticalPadding * 2;
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
    final gridY = (local.dy - widget.homeTopInset - _verticalPadding)
        .clamp(0.0, gridHeight);
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

    final layout = _layoutFor(current);
    final rawPage = _controller.page ?? _controller.initialPage.toDouble();
    final section = layout.sectionFor(rawPage.round());

    // Parked on a special page without an explicit navigation: keep the user
    // there. Only re-pin the trailing Library if the home page count shifted
    // (e.g. an empty page was collapsed after a package removal).
    if (!currentPageChanged && section != HomeSection.home) {
      if (section == HomeSection.library && pageCountChanged) {
        final target = layout.itemCount - 1;
        if (rawPage.round() != target) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_controller.hasClients) return;
            _controller.jumpToPage(target);
          });
        }
      }
      return;
    }

    final targetPage =
        current.currentPage.clamp(0, current.pages.length - 1).toInt();
    final controllerTarget = layout.homeToController(targetPage);
    final roundedPage = rawPage.round();
    final controllerOutOfRange = roundedPage >= layout.itemCount;
    if (!controllerOutOfRange && roundedPage == controllerTarget) return;

    dragDropLog(
      '[WidgetDragDrop][workspace] syncPageController '
      'rawPage=${rawPage.toStringAsFixed(3)} target=$controllerTarget '
      'pages=${previous.pages.length}->${current.pages.length} '
      'statePage=${previous.currentPage}->${current.currentPage}',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients || current.pages.isEmpty) return;
      final l = _layoutFor(current);
      final safeTarget =
          current.currentPage.clamp(0, current.pages.length - 1).toInt();
      _controller.jumpToPage(l.homeToController(safeTarget));
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
        final layout = _layoutFor(state);
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
              onPageChanged: (i) {
                if (_effectiveInfinite) {
                  context
                      .read<WorkspaceCubit>()
                      .setCurrentPage(i % state.pages.length);
                  widget.onSectionSettled?.call(HomeSection.home);
                  return;
                }
                final section = layout.sectionFor(i);
                if (section == HomeSection.home) {
                  context
                      .read<WorkspaceCubit>()
                      .setCurrentPage(layout.homeIndexFor(i));
                }
                widget.onSectionSettled?.call(section);
              },
              itemCount: _effectiveInfinite ? null : layout.itemCount,
              itemBuilder: (context, rawIndex) {
                if (_effectiveInfinite) {
                  final i = rawIndex % state.pages.length;
                  return _buildHomePage(context, state, i);
                }
                switch (layout.sectionFor(rawIndex)) {
                  case HomeSection.discover:
                    return widget.discoverBuilder!(context);
                  case HomeSection.library:
                    return widget.libraryBuilder!(context);
                  case HomeSection.home:
                    return _buildHomePage(
                        context, state, layout.homeIndexFor(rawIndex));
                }
              },
            );
          },
        );
      },
    );
  }

  Widget _buildHomePage(BuildContext context, WorkspaceState state, int i) {
    final cell = CellLayoutView(
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
    if (widget.homeTopInset == 0 && widget.homeBottomInset == 0) return cell;
    return Padding(
      padding: EdgeInsets.only(
        top: widget.homeTopInset,
        bottom: widget.homeBottomInset,
      ),
      child: cell,
    );
  }
}
