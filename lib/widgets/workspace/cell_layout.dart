import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../models/folder_info.dart';
import '../../models/item_info.dart';
import '../../models/launcher_settings.dart';
import '../../models/launcher_widget_info.dart';
import '../../models/workspace_item_info.dart';
import '../../services/drag/drag_controller.dart';
import '../../services/gestures/widget_resize_gesture_guard.dart';
import '../../services/launcher_service.dart';
import '../../state/apps_cubit.dart';
import '../../state/settings_cubit.dart';
import '../../state/workspace_cubit.dart';
import '../../utils/debug_flags.dart';
import '../drag/pickup_feedback.dart';
import '../folder/folder_icon.dart';
import '../folder/folder_view.dart';
import '../icons/badge_listener.dart';
import '../icons/bubble_text_view.dart';
import 'home_widget_slot.dart';
import 'home_widget_stack_view.dart';
import 'widget_grid_math.dart';

// sourcePage == -3 means the drag originated from the app drawer (no removal needed)
const int kDrawerSourcePage = -3;

class CellLayoutView extends StatefulWidget {
  final WorkspacePage page;
  final int pageIndex;
  final LauncherSettings settings;
  final DragController dragController;
  final void Function(AppInfo app) onAppTap;
  final void Function(AppInfo app, int slot, Offset iconCenter) onAppLongPress;
  final VoidCallback onBackgroundLongPress;

  /// Invoked when the user taps "Create stack" / "Add widget" on the action
  /// menu. The host opens the widget picker and, when a widget is chosen,
  /// merges it into the slot at (page, slot).
  final void Function(int page, int slot)? onPickWidgetForStack;

  const CellLayoutView({
    super.key,
    required this.page,
    required this.pageIndex,
    required this.settings,
    required this.dragController,
    required this.onAppTap,
    required this.onAppLongPress,
    required this.onBackgroundLongPress,
    this.onPickWidgetForStack,
  });

  @override
  State<CellLayoutView> createState() => _CellLayoutViewState();
}

class _CellLayoutViewState extends State<CellLayoutView>
    with TickerProviderStateMixin {
  // Intentionally not AutomaticKeepAliveClientMixin: keep-alive holds every
  // visited page's AndroidView host surfaces live but undrained while off-
  // screen, overflowing the hybrid-composition ImageReader buffer pool
  // ("Unable to acquire a buffer item"). PageView.allowImplicitScrolling=true
  // already keeps the adjacent page warm, which is the only one worth paying
  // for. Distant pages rebuild from WorkspaceCubit state on return — there
  // is no in-page scroll/animation state worth preserving.
  static const double _gridGap = 8;
  static const int _resizeHorizontal = 1;
  static const int _resizeVertical = 2;
  static const double _widgetLongPressHitOutset =
      _WorkspaceWidgetResizeFrame.touchOutset;
  static const Duration _widgetMetadataRefreshDelay =
      Duration(milliseconds: 1600);

  static const double _widgetDragActivationDistance = 8;
  int? _draggingSlot;
  int? _selectedWidgetSlot;
  // Tracks whether we've incremented WidgetResizeGestureGuard for the current
  // selection. While a widget is selected the workspace PageView switches to
  // NeverScrollableScrollPhysics (see workspace_view.dart), which removes
  // its drag recognizer from the gesture arena entirely — that's the only
  // reliable way to keep a body-swipe from paging through, since arena
  // competition with the PageView's drag recognizer can race.
  bool _selectionGuardActive = false;
  // Hides the floating action menu (info / Create stack / Remove) for the
  // remainder of the current selection once the user starts dragging or
  // resizing. A fresh long-press re-selection resets this back to false.
  bool _menuHiddenForGesture = false;
  int? _armedWidgetDragSlot;
  double _armedWidgetDragDistance = 0;
  final ValueNotifier<int?> _activeWidgetDragFeedbackSlot =
      ValueNotifier<int?>(null);

  // Commit-displacement timers (widget-over-app: 240ms, app-over-app: 650ms)
  final Map<int, Timer> _displacementTimers = {};
  // Preview-animation timers (fires at 350ms for app-over-app)
  final Map<int, Timer> _previewTimers = {};
  // Per-slot animation controllers driving the pre-displacement slide
  final Map<int, AnimationController> _displacementPreviewControllers = {};
  // Direction the icon slides (unit grid vector, e.g. Offset(-1,0) = left)
  final Map<int, Offset> _displacementPreviewDirections = {};
  // Maps source slot → destination ghost slot
  final Map<int, int> _previewDestSlots = {};
  // Slots that show a ghost "landing zone" outline during preview
  final Set<int> _ghostDestinationSlots = {};
  // Slots showing folder-creation color preview (dragged app covers ≥80% of tile)
  final Set<int> _folderPreviewSlots = {};
  // Key used to convert global drag coordinates to local Stack space
  final GlobalKey _stackKey = GlobalKey();
  // Latest cell dimensions — updated each build, used for overlap math
  double _cellWidth = 0;
  double _cellHeight = 0;
  int? _widgetDropPreviewPointerSlot;
  int? _widgetDropPreviewAnchorSlot;
  int _widgetDropPreviewSpanX = 1;
  int _widgetDropPreviewSpanY = 1;
  static String? _lastWidgetMetadataRefreshKey;
  // Cell dimensions last observed when we requested a widget metadata refresh.
  // Gating the post-frame schedule on these avoids re-entering the dedupe path
  // (and its string/key work) on every PageView scroll frame.
  double _lastRefreshedCellWidth = -1;
  double _lastRefreshedCellHeight = -1;
  // Debounce trailing widget-metadata refreshes — pushing/popping the drawer
  // route shifts cell dimensions by sub-pixel amounts and triggers a slow
  // AppWidgetManager IPC binder call that blocks the platform thread for
  // 100-200ms. Collapse rapid sequential triggers into one trailing call.
  Timer? _widgetMetadataRefreshDebounce;
  OverlayEntry? _openFolderEntry;
  String? _openFolderId;

  // Memo for _occupiedWidgetSlots(ignoreAnchorSlot: null). Keyed by page
  // identity + grid dims. Build() and several drag paths call this on every
  // frame during pointer activity, but the page slots only change on
  // WorkspaceCubit emits — so we cache the result and invalidate when any
  // of the inputs differ.
  WorkspacePage? _occupiedMemoPage;
  int _occupiedMemoCols = -1;
  int _occupiedMemoRows = -1;
  Set<int>? _occupiedMemoResult;

  @override
  void initState() {
    super.initState();
    WidgetResizeGestureGuard.isHandlePointerActiveNotifier
        .addListener(_onResizeGuardChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _normalizePersistedWidgetSpans();
    });
  }

  // Hide the action menu the moment a resize handle is pressed. Bound to the
  // dedicated handle-pointer notifier (not isResizingNotifier) because the
  // selection is usually already active when the handle is grabbed, so
  // isResizing wouldn't change value.
  void _onResizeGuardChanged() {
    if (!mounted) return;
    if (_selectedWidgetSlot == null) return;
    if (!WidgetResizeGestureGuard.isHandlePointerActive) return;
    if (_menuHiddenForGesture) return;
    setState(() => _menuHiddenForGesture = true);
  }

  @override
  void didUpdateWidget(covariant CellLayoutView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _normalizePersistedWidgetSpans();
      });
    }
  }

  @override
  void dispose() {
    WidgetResizeGestureGuard.isHandlePointerActiveNotifier
        .removeListener(_onResizeGuardChanged);
    _widgetMetadataRefreshDebounce?.cancel();
    _closeOpenFolder();
    for (final t in _previewTimers.values) {
      t.cancel();
    }
    _previewTimers.clear();
    for (final t in _displacementTimers.values) {
      t.cancel();
    }
    _displacementTimers.clear();
    for (final ctrl in _displacementPreviewControllers.values) {
      ctrl.dispose();
    }
    _displacementPreviewControllers.clear();
    _activeWidgetDragFeedbackSlot.dispose();
    if (_selectionGuardActive) {
      WidgetResizeGestureGuard.setSelectionActive(false);
      WidgetResizeGestureGuard.onRequestDismiss = null;
      _selectionGuardActive = false;
    }
    super.dispose();
  }

  /// Keeps the global gesture guard in lock-step with `_selectedWidgetSlot`.
  /// Called both from `build()` (catch-all) and imperatively from every
  /// setState site that mutates `_selectedWidgetSlot`, so the lock can never
  /// drift from the visible selection state.
  void _syncSelectionGuard() {
    final shouldBeActive = _selectedWidgetSlot != null;
    if (shouldBeActive == _selectionGuardActive) return;
    _selectionGuardActive = shouldBeActive;
    WidgetResizeGestureGuard.setSelectionActive(shouldBeActive);
    if (shouldBeActive) {
      // Register a dismiss hook so external gesture paths (the dock's
      // own GestureDetector, the workspace_touch_listener's raw
      // Listener, etc.) can ask edit mode to exit when they would
      // otherwise fire an action that should instead dismiss.
      WidgetResizeGestureGuard.onRequestDismiss = _clearWidgetResizeSelection;
    } else {
      WidgetResizeGestureGuard.onRequestDismiss = null;
    }
  }

  void _closeOpenFolder([String? folderId]) {
    if (folderId != null && _openFolderId != folderId) return;
    _openFolderEntry?.remove();
    _openFolderEntry = null;
    _openFolderId = null;
  }

  void _cancelAllDisplacementTimers() {
    for (final t in _previewTimers.values) {
      t.cancel();
    }
    _previewTimers.clear();
    for (final t in _displacementTimers.values) {
      t.cancel();
    }
    _displacementTimers.clear();
    final slots = _displacementPreviewControllers.keys.toList();
    for (final slot in slots) {
      _reversePreviewAnimation(slot);
    }
    if (mounted) {
      setState(() {
        _ghostDestinationSlots.clear();
        _folderPreviewSlots.clear();
        _clearWidgetDropPreviewState();
      });
    }
  }

  void _clearWidgetDropPreviewState() {
    _widgetDropPreviewPointerSlot = null;
    _widgetDropPreviewAnchorSlot = null;
    _widgetDropPreviewSpanX = 1;
    _widgetDropPreviewSpanY = 1;
  }

  void _clearWidgetDropPreview([int? pointerSlot]) {
    if (_widgetDropPreviewPointerSlot == null &&
        _widgetDropPreviewAnchorSlot == null) {
      return;
    }
    if (pointerSlot != null && _widgetDropPreviewPointerSlot != pointerSlot) {
      return;
    }
    if (!mounted) {
      _clearWidgetDropPreviewState();
      return;
    }
    setState(_clearWidgetDropPreviewState);
  }

  void _clearWidgetResizeSelection() {
    if (_selectedWidgetSlot == null) return;
    setState(() {
      _selectedWidgetSlot = null;
      _menuHiddenForGesture = false;
    });
    _syncSelectionGuard();
  }

  bool _dismissWidgetResizeSelectionIfActive() {
    if (_selectedWidgetSlot == null && !WidgetResizeGestureGuard.isResizing) {
      return false;
    }
    _clearWidgetResizeSelection();
    return true;
  }

  void _openBackgroundEditMenu() {
    _clearWidgetResizeSelection();
    widget.onBackgroundLongPress();
  }

  void _handleBackgroundLongPressStart(
    LongPressStartDetails details,
    double cellWidth,
    double cellHeight,
  ) {
    final edgeSlot = _widgetSlotNearPoint(
      details.localPosition,
      cellWidth,
      cellHeight,
    );
    if (edgeSlot != null) {
      setState(() {
        _selectedWidgetSlot = edgeSlot;
        _draggingSlot = null;
        _armedWidgetDragSlot = null;
        _armedWidgetDragDistance = 0;
        _menuHiddenForGesture = false;
      });
      _syncSelectionGuard();
      return;
    }
    _openBackgroundEditMenu();
  }

  bool _isWidgetDragActive(int slot) {
    return _activeWidgetDragFeedbackSlot.value == slot;
  }

  void _armWidgetDrag(int slot) {
    // If this same slot is already selected with the menu deliberately
    // hidden (e.g. user just finished a resize), keep it hidden — a
    // long-press to move shouldn't bring the info menu back. Only surface
    // the menu on a fresh selection (different slot or none selected).
    final isReselectionOfHiddenMenu =
        _selectedWidgetSlot == slot && _menuHiddenForGesture;
    setState(() {
      _draggingSlot = slot;
      _selectedWidgetSlot = slot;
      _armedWidgetDragSlot = slot;
      _armedWidgetDragDistance = 0;
      if (!isReselectionOfHiddenMenu) {
        _menuHiddenForGesture = false;
      }
    });
    _syncSelectionGuard();
    _activeWidgetDragFeedbackSlot.value = null;
  }

  void _maybeActivateWidgetDrag(
    DragUpdateDetails details,
    DragPayload payload,
    int slot,
  ) {
    if (_armedWidgetDragSlot != slot || _isWidgetDragActive(slot)) return;

    _armedWidgetDragDistance += details.delta.distance;
    if (_armedWidgetDragDistance < _widgetDragActivationDistance) return;

    setState(() {
      _selectedWidgetSlot = null;
      // If onDragEnd later re-selects this slot (cancelled drag), keep the
      // menu hidden so it only reappears on a fresh long-press. Matches
      // user spec: "stay hidden until re-selected".
      _menuHiddenForGesture = true;
    });
    _syncSelectionGuard();
    _activeWidgetDragFeedbackSlot.value = slot;
    widget.dragController
        .startDrag(payload.item, widget.pageIndex, slot, Offset.zero);
  }

  void _finishWidgetDrag(int slot, {required bool wasAccepted}) {
    final wasActive = _isWidgetDragActive(slot);
    setState(() {
      _draggingSlot = null;
      _armedWidgetDragSlot = null;
      _armedWidgetDragDistance = 0;
      _selectedWidgetSlot =
          wasAccepted && wasActive ? _selectedWidgetSlot : slot;
    });
    _syncSelectionGuard();
    _activeWidgetDragFeedbackSlot.value = null;
    _cancelAllDisplacementTimers();
    if (wasActive) {
      widget.dragController.cancelDrag();
    }
  }

  void _completeWidgetDrag(int slot) {
    setState(() {
      _draggingSlot = null;
      _armedWidgetDragSlot = null;
      _armedWidgetDragDistance = 0;
    });
    _activeWidgetDragFeedbackSlot.value = null;
    _cancelAllDisplacementTimers();
  }

  // withPreview=true  → 350ms preview slide + 650ms commit (app-over-app)
  // withPreview=false → 240ms commit only (widget-over-app, existing behaviour)
  void _startDisplacementTimer(
    int slot,
    WorkspaceCubit workspace,
    LauncherSettings settings, {
    bool withPreview = false,
    Offset preferredDirection = Offset.zero,
  }) {
    if (_displacementTimers.containsKey(slot)) return;

    if (withPreview) {
      final path = _findDisplacementPath(
        slot,
        settings.gridColumns,
        settings.gridRows,
        preferredDirection: preferredDirection,
      );
      if (path == null) return; // no room — skip entirely

      final direction =
          _displacementDirectionFromPath(slot, path, settings.gridColumns);
      final destSlot = path[path.length - 2];

      _previewTimers[slot] = Timer(const Duration(milliseconds: 350), () {
        _previewTimers.remove(slot);
        if (mounted) _startPreviewAnimation(slot, direction, destSlot);
      });

      _displacementTimers[slot] = Timer(const Duration(milliseconds: 650), () {
        _displacementTimers.remove(slot);
        _stopPreviewAnimation(slot);
        _tryDisplaceApp(slot, workspace, settings,
            preferredDirection: preferredDirection);
      });
    } else {
      _displacementTimers[slot] = Timer(const Duration(milliseconds: 240), () {
        _displacementTimers.remove(slot);
        _tryDisplaceApp(slot, workspace, settings);
      });
    }
  }

  void _cancelDisplacementTimer(int slot) {
    _previewTimers[slot]?.cancel();
    _previewTimers.remove(slot);
    _displacementTimers[slot]?.cancel();
    _displacementTimers.remove(slot);
    _reversePreviewAnimation(slot);
    if (_folderPreviewSlots.contains(slot) && mounted) {
      setState(() => _folderPreviewSlots.remove(slot));
    }
  }

  // Returns the unit direction an app at [slot] should slide given [path].
  // path is [emptySlot, ..., slot] so path[length-2] is the immediate neighbour
  // the app moves toward.
  Offset _displacementDirectionFromPath(int slot, List<int> path, int cols) {
    if (path.length < 2) return Offset.zero;
    final nextSlot = path[path.length - 2];
    final dx = ((nextSlot % cols) - (slot % cols)).toDouble();
    final dy = ((nextSlot ~/ cols) - (slot ~/ cols)).toDouble();
    return Offset(dx, dy);
  }

  void _startPreviewAnimation(int slot, Offset direction, int destSlot) {
    if (!mounted) return;
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _displacementPreviewControllers[slot] = ctrl;
    _displacementPreviewDirections[slot] = direction;
    _previewDestSlots[slot] = destSlot;
    setState(() => _ghostDestinationSlots.add(destSlot));
    ctrl.forward();
  }

  // Called when displacement commits: remove preview state without reversing.
  void _stopPreviewAnimation(int slot) {
    final ctrl = _displacementPreviewControllers.remove(slot);
    _displacementPreviewDirections.remove(slot);
    final dest = _previewDestSlots.remove(slot);
    ctrl?.dispose();
    if (dest != null && mounted) {
      setState(() => _ghostDestinationSlots.remove(dest));
    }
  }

  // Called when drag leaves or is cancelled: reverse the slide animation first.
  void _reversePreviewAnimation(int slot) {
    final ctrl = _displacementPreviewControllers.remove(slot);
    _displacementPreviewDirections.remove(slot);
    final dest = _previewDestSlots.remove(slot);
    if (ctrl != null) {
      ctrl.reverse().whenComplete(ctrl.dispose);
    }
    if (dest != null && mounted) {
      setState(() => _ghostDestinationSlots.remove(dest));
    }
  }

  // Converts a global drag pointer position to local coordinates inside the
  // slot tile. Returns null if the Stack RenderBox is not yet available.
  Offset? _localPositionInSlot(Offset globalPos, int slot) {
    if (_cellWidth <= 0 || _cellHeight <= 0) return null;
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final localInStack = box.globalToLocal(globalPos);
    final tileOrigin = _slotRect(slot, _cellWidth, _cellHeight).topLeft;
    return localInStack - tileOrigin;
  }

  // Fraction of the app icon area (iconSize × iconSize) that the dragged icon
  // covers when the pointer is at [localPos] in tile-local coordinates.
  // Both icons are iconSize × iconSize; the target icon is centred in the tile.
  double _overlapFraction(Offset localPos) {
    final iconSize = widget.settings.iconSize.toDouble();
    final dx = (localPos.dx - _cellWidth / 2).abs();
    final dy = (localPos.dy - _cellHeight / 2).abs();
    final overlapX = (iconSize - dx).clamp(0.0, iconSize);
    final overlapY = (iconSize - dy).clamp(0.0, iconSize);
    return (overlapX * overlapY) / (iconSize * iconSize);
  }

  // Direction the displaced app should move, derived from where the drag entered.
  // The drag entered from the side closest to localPos, so push the existing app
  // in the direction from localPos toward the tile center.
  Offset _pushDirectionFromLocalPos(Offset localPos) {
    final dx = _cellWidth / 2 - localPos.dx;
    final dy = _cellHeight / 2 - localPos.dy;
    if (dx.abs() >= dy.abs()) {
      return dx > 0 ? const Offset(1, 0) : const Offset(-1, 0);
    } else {
      return dy > 0 ? const Offset(0, 1) : const Offset(0, -1);
    }
  }

  // True when moving from [fromSlot] to [neighborSlot] matches [direction].
  bool _matchesDirection(
      int neighborSlot, int fromSlot, Offset direction, int cols) {
    final dx = (neighborSlot % cols) - (fromSlot % cols);
    final dy = (neighborSlot ~/ cols) - (fromSlot ~/ cols);
    return (direction.dx != 0 && dx.sign == direction.dx.sign) ||
        (direction.dy != 0 && dy.sign == direction.dy.sign);
  }

  bool _tryDisplaceApp(
    int appSlot,
    WorkspaceCubit workspace,
    LauncherSettings settings, {
    int? ignoreSlot,
    Offset preferredDirection = Offset.zero,
  }) {
    final path = _findDisplacementPath(
      appSlot,
      settings.gridColumns,
      settings.gridRows,
      ignoreSlot: ignoreSlot,
      preferredDirection: preferredDirection,
    );
    if (path == null) return false;

    if (workspace.shiftItemsAlongPath(widget.pageIndex, path)) {
      for (int i = 0; i < path.length - 1; i++) {
        widget.dragController.recordDisplacement(
          widget.pageIndex,
          path[i],
          path[i + 1],
        );
      }
      return true;
    }
    return false;
  }

  /// Returns the set of grid slots currently occupied by the widget being
  /// dragged, if the drag originated on this page. Used to distinguish
  /// "covered by the source widget itself" from "covered by another widget",
  /// so those slots can still receive DragTargets and be accepted as drops.
  Set<int> _sourceWidgetCoverage(DragPayload? payload) {
    if (payload == null || !payload.isWidget) return const {};
    if (payload.sourcePage != widget.pageIndex) return const {};
    final sourceContent = widget.page.slots[payload.sourceSlot];
    final (spanX, spanY) = _effectiveSpanForContent(sourceContent);
    if (spanX == 0 || spanY == 0) return const {};
    return {
      ...?slotsForSpan(
        payload.sourceSlot,
        spanX,
        spanY,
        widget.settings.gridColumns,
        widget.settings.gridRows,
      ),
    };
  }

  List<int> _adjacentSlots(int slot, int cols, int rows) {
    final total = cols * rows;
    final col = slot % cols;
    final result = <int>[];
    if (col < cols - 1) result.add(slot + 1); // right
    if (col > 0) result.add(slot - 1); // left
    if (slot + cols < total) result.add(slot + cols); // below
    if (slot - cols >= 0) result.add(slot - cols); // above
    return result;
  }

  List<int>? _findDisplacementPath(
    int startSlot,
    int cols,
    int rows, {
    int? ignoreSlot,
    // Pass the live workspace page when calling from _onDrop after earlier
    // displacements have already shifted slots — widget.page is stale then.
    WorkspacePage? page,
    // When set, neighbors in this direction are explored first so the displaced
    // app moves in the preferred direction before trying other directions.
    Offset preferredDirection = Offset.zero,
  }) {
    final sourcePage = page ?? widget.page;
    final coveredSlots = _occupiedWidgetSlots(
      sourcePage,
      cols,
      rows,
      ignoreAnchorSlot: ignoreSlot,
    );
    final queue = <int>[startSlot];
    final previous = <int, int?>{startSlot: null};

    while (queue.isNotEmpty) {
      final slot = queue.removeAt(0);
      final neighbors = _adjacentSlots(slot, cols, rows);
      // Bias BFS: try the preferred direction first at each step.
      if (preferredDirection != Offset.zero) {
        neighbors.sort((a, b) {
          final aMatch = _matchesDirection(a, slot, preferredDirection, cols);
          final bMatch = _matchesDirection(b, slot, preferredDirection, cols);
          if (aMatch == bMatch) return 0;
          return aMatch ? -1 : 1;
        });
      }
      for (final next in neighbors) {
        if (previous.containsKey(next)) continue;
        if (coveredSlots.contains(next)) continue;

        final content = next == ignoreSlot ? null : sourcePage.slots[next];
        if (content is WidgetSlot || content is WidgetStackSlot) continue;

        previous[next] = slot;
        if (content == null || content is EmptySlot) {
          final path = <int>[next];
          int? cursor = slot;
          while (cursor != null) {
            path.add(cursor);
            cursor = previous[cursor];
          }
          return path.reversed.toList();
        }

        queue.add(next);
      }
    }

    return null;
  }

  void _removeDockPackage(BuildContext context, int dockSlot) {
    final settings = context.read<SettingsCubit>().state;
    final packages = List<String>.from(settings.dockPackages);
    if (dockSlot < packages.length) packages[dockSlot] = '';
    context
        .read<SettingsCubit>()
        .update(settings.copyWith(dockPackages: packages));
  }

  void _onDrop(
      BuildContext context, DragTargetDetails<DragPayload> details, int slot) {
    // Capture folder-creation intent BEFORE _cancelAllDisplacementTimers clears it.
    final isFolderCreationDrop = _folderPreviewSlots.contains(slot);
    // Always commit displacements on any successful drop
    widget.dragController.commitDisplacements();
    _cancelAllDisplacementTimers();

    final payload = details.data;
    final workspace = context.read<WorkspaceCubit>();
    final livePage =
        widget.pageIndex >= 0 && widget.pageIndex < workspace.state.pages.length
            ? workspace.state.pages[widget.pageIndex]
            : widget.page;
    final target = livePage.slots[slot];

    if (!payload.isWidget) {
      _clearWidgetResizeSelection();
    }

    // ── Widget drag ────────────────────────────────────────────────────────────
    if (payload.isWidget) {
      final settings = context.read<SettingsCubit>().state;
      final (spanX, spanY) = _spanForWidgetPayload(payload, workspace);
      final resolvedSlot = _resolveWidgetAnchorSlot(
        payload: payload,
        pointerSlot: slot,
        spanX: spanX,
        spanY: spanY,
        workspace: workspace,
      );
      if (resolvedSlot == null) {
        widget.dragController.cancelDrag();
        _clearWidgetDropPreview();
        return;
      }
      final targetPage = widget.pageIndex >= 0 &&
              widget.pageIndex < workspace.state.pages.length
          ? workspace.state.pages[widget.pageIndex]
          : widget.page;
      final resolvedTarget = targetPage.slots[resolvedSlot];

      if (resolvedTarget is WidgetSlot || resolvedTarget is WidgetStackSlot) {
        // Stack the two widgets together
        workspace.createWidgetStack(
          payload.sourcePage,
          payload.sourceSlot,
          widget.pageIndex,
          resolvedSlot,
          maxSpanY: _stackMaxRowSpan(),
        );
      } else if (resolvedTarget is AppSlot) {
        final path = _findDisplacementPath(
          resolvedSlot,
          settings.gridColumns,
          settings.gridRows,
          ignoreSlot: payload.sourcePage == widget.pageIndex
              ? payload.sourceSlot
              : null,
        );
        if (path == null ||
            !workspace.moveItemWithDisplacement(
              payload.sourcePage,
              payload.sourceSlot,
              widget.pageIndex,
              resolvedSlot,
              path,
            )) {
          widget.dragController.cancelDrag();
          return;
        }
      } else {
        // Empty slot (or a slot that was in the source widget's coverage).
        // First displace any apps that sit inside the widget's target span —
        // this handles the case where _willAccept accepted a span with apps.
        final cols = settings.gridColumns;
        final rows = settings.gridRows;
        final ignoreSource =
            payload.sourcePage == widget.pageIndex ? payload.sourceSlot : null;
        final targetCovered =
            slotsForSpan(resolvedSlot, spanX, spanY, cols, rows) ?? const [];
        for (final targetSlot in targetCovered) {
          if (targetSlot == ignoreSource) continue;
          // Re-read the live page each iteration because earlier iterations
          // may have shifted items.
          final livePage = workspace.state.pages[widget.pageIndex];
          final slotContent = livePage.slots[targetSlot];
          if (slotContent is AppSlot) {
            final path = _findDisplacementPath(
              targetSlot,
              cols,
              rows,
              ignoreSlot: ignoreSource,
              page: livePage,
            );
            if (path != null) {
              workspace.shiftItemsAlongPath(widget.pageIndex, path);
              for (int i = 0; i < path.length - 1; i++) {
                widget.dragController
                    .recordDisplacement(widget.pageIndex, path[i], path[i + 1]);
              }
            }
          }
        }
        workspace.moveItem(
          payload.sourcePage,
          payload.sourceSlot,
          widget.pageIndex,
          resolvedSlot,
        );
      }
      workspace.collapseEmptyPages();
      widget.dragController.cancelDrag();
      _clearWidgetDropPreview();
      if (mounted) {
        setState(() => _selectedWidgetSlot = resolvedSlot);
        _syncSelectionGuard();
      }
      return;
    }

    // ── Normal app/folder drag ─────────────────────────────────────────────────

    if (payload.folderId != null) {
      final item = payload.item;
      if (item is WorkspaceItemInfo) {
        if (target is FolderSlot) {
          workspace.addToFolder(target.folderId, item);
        } else {
          workspace.addItem(item, widget.pageIndex, slot);
        }
        workspace.removeFromFolder(payload.folderId!, item);
        final remaining =
            workspace.state.folders[payload.folderId!]?.contents.length ?? 0;
        if (remaining <= 1) {
          workspace.tryCollapseFolder(
              payload.folderId!, payload.folderPage, payload.folderSlot);
        }
      }
      workspace.collapseEmptyPages();
      widget.dragController.cancelDrag();
      payload.onFolderDropCompleted?.call();
      return;
    }

    if (payload.sourcePage == kDrawerSourcePage) {
      final item = payload.item;
      if (item is WorkspaceItemInfo) {
        if (target is FolderSlot) {
          workspace.addToFolder(target.folderId, item);
        } else if (target is AppSlot) {
          final settings = context.read<SettingsCubit>().state;
          if (!_tryDisplaceApp(slot, workspace, settings)) {
            widget.dragController.cancelDrag();
            return;
          }
          workspace.addItem(item, widget.pageIndex, slot);
        } else {
          workspace.addItem(item, widget.pageIndex, slot);
        }
        workspace.collapseEmptyPages();
      }
      widget.dragController.cancelDrag();
      return;
    }

    if (target is FolderSlot) {
      final item = payload.item;
      if (item is WorkspaceItemInfo && item.itemType == ItemType.application) {
        final added = workspace.addToFolder(target.folderId, item);
        if (added) {
          if (payload.sourcePage >= 0) {
            workspace.removeItem(payload.sourcePage, payload.sourceSlot);
          } else if (payload.sourcePage == -1) {
            _removeDockPackage(context, payload.sourceSlot);
          }
        }
      } else {
        if (payload.sourcePage >= 0) {
          workspace.moveItem(
              payload.sourcePage, payload.sourceSlot, widget.pageIndex, slot);
        }
      }
    } else if (target is AppSlot && payload.sourcePage >= 0) {
      final item = payload.item;
      if (isFolderCreationDrop && item is WorkspaceItemInfo) {
        // Dragged app covered ≥80% of tile — create a folder instead of displacing.
        if (payload.sourcePage == widget.pageIndex) {
          workspace.createFolder(
              widget.pageIndex, payload.sourceSlot, slot, '');
        } else if (payload.sourcePage == kDrawerSourcePage) {
          workspace.createFolderFromExternal(item, widget.pageIndex, slot, '');
        } else {
          workspace.createFolderFromExternal(item, widget.pageIndex, slot, '');
          workspace.removeItem(payload.sourcePage, payload.sourceSlot);
        }
      } else {
        final settings = context.read<SettingsCubit>().state;
        final path = _findDisplacementPath(
          slot,
          settings.gridColumns,
          settings.gridRows,
          ignoreSlot: payload.sourcePage == widget.pageIndex
              ? payload.sourceSlot
              : null,
        );
        final moved = path == null
            ? workspace.swapItems(
                payload.sourcePage,
                payload.sourceSlot,
                widget.pageIndex,
                slot,
              )
            : workspace.moveItemWithDisplacement(
                payload.sourcePage,
                payload.sourceSlot,
                widget.pageIndex,
                slot,
                path,
              );
        if (!moved) {
          widget.dragController.cancelDrag();
          return;
        }
      }
    } else {
      if (payload.sourcePage >= 0) {
        workspace.moveItem(
            payload.sourcePage, payload.sourceSlot, widget.pageIndex, slot);
      } else if (payload.sourcePage == -1) {
        final item = payload.item;
        if (item is WorkspaceItemInfo) {
          workspace.addItem(item, widget.pageIndex, slot);
          _removeDockPackage(context, payload.sourceSlot);
        }
      }
    }

    workspace.collapseEmptyPages();
    widget.dragController.cancelDrag();
  }

  bool _willAccept(
    DragPayload payload,
    SlotContent? target,
    int slot,
    WorkspaceCubit workspace,
  ) {
    final coveredSlots = _occupiedWidgetSlots(
      widget.page,
      widget.settings.gridColumns,
      widget.settings.gridRows,
    );
    final isWidgetAnchor = target is WidgetSlot || target is WidgetStackSlot;

    // Slots covered by the SOURCE widget being dragged must not be treated as
    // "covered by another widget" — they will be freed once the widget moves.
    final sourceWidgetCoverage = _sourceWidgetCoverage(payload);
    final isCoveredByAnotherWidget = coveredSlots.contains(slot) &&
        !isWidgetAnchor &&
        !sourceWidgetCoverage.contains(slot);

    // Reject same-slot drops
    if (payload.sourcePage == widget.pageIndex && payload.sourceSlot == slot) {
      return false;
    }
    if (isCoveredByAnotherWidget) return false;
    if (!payload.isWidget && isWidgetAnchor) return false;

    if (payload.isWidget) {
      if (target is FolderSlot) return false;
      if (isWidgetAnchor) return true;

      final (spanX, spanY) = _spanForWidgetPayload(payload, workspace);

      return _resolveWidgetAnchorSlot(
            payload: payload,
            pointerSlot: slot,
            spanX: spanX,
            spanY: spanY,
            workspace: workspace,
          ) !=
          null;
    }
    if (target is AppSlot) {
      if (payload.sourcePage >= 0) return true;
      return _findDisplacementPath(
            slot,
            widget.settings.gridColumns,
            widget.settings.gridRows,
            ignoreSlot: payload.sourcePage == widget.pageIndex
                ? payload.sourceSlot
                : null,
          ) !=
          null;
    }
    return true;
  }

  /// Like [canPlaceWidgetAt] but treats app-occupied slots as valid — those
  /// apps will be displaced when the widget is dropped. Only another widget
  /// or a folder hard-blocks the placement.
  bool _canPlaceWidgetAllowingAppDisplacement({
    required int anchorSlot,
    required int spanX,
    required int spanY,
    int? ignoreAnchorSlot,
  }) {
    final covered = slotsForSpan(
      anchorSlot,
      spanX,
      spanY,
      widget.settings.gridColumns,
      widget.settings.gridRows,
    );
    if (covered == null) return false;

    final ignoredCoverage = ignoreAnchorSlot == null
        ? const <int>{}
        : _currentWidgetCoverage(
            widget.page,
            ignoreAnchorSlot,
            widget.settings.gridColumns,
            widget.settings.gridRows,
          );
    final occupiedByOtherWidgets = _occupiedWidgetSlots(
      widget.page,
      widget.settings.gridColumns,
      widget.settings.gridRows,
      ignoreAnchorSlot: ignoreAnchorSlot,
    );

    for (final s in covered) {
      if (occupiedByOtherWidgets.contains(s)) return false;
      if (ignoredCoverage.contains(s)) continue;
      final content = widget.page.slots[s];
      if (content is FolderSlot) return false;
      // AppSlot and empty are fine — apps displaced at drop time.
    }
    return true;
  }

  (int, int) _spanForWidgetContent(SlotContent? content) {
    final (spanX, spanY) = _effectiveSpanForContent(content);
    if (spanX == 0 || spanY == 0) return (1, 1);
    return (spanX, spanY);
  }

  (int, int) _spanForWidgetPayload(
    DragPayload payload,
    WorkspaceCubit workspace,
  ) {
    final sourceContent = payload.sourcePage >= 0 &&
            payload.sourcePage < workspace.state.pages.length
        ? workspace.state.pages[payload.sourcePage].slots[payload.sourceSlot]
        : null;
    final (contentSpanX, contentSpanY) = _spanForWidgetContent(sourceContent);
    if (contentSpanX > 1 || contentSpanY > 1) {
      return (contentSpanX, contentSpanY);
    }
    return (
      payload.item.spanX.clamp(1, widget.settings.gridColumns).toInt(),
      payload.item.spanY.clamp(1, widget.settings.gridRows).toInt(),
    );
  }

  void _updateWidgetDropPreview(
    DragPayload payload,
    int pointerSlot,
    WorkspaceCubit workspace,
  ) {
    if (!payload.isWidget) {
      _clearWidgetDropPreview(pointerSlot);
      return;
    }

    final (spanX, spanY) = _spanForWidgetPayload(payload, workspace);
    final anchorSlot = _resolveWidgetAnchorSlot(
      payload: payload,
      pointerSlot: pointerSlot,
      spanX: spanX,
      spanY: spanY,
      workspace: workspace,
    );
    if (anchorSlot == null) {
      _clearWidgetDropPreview(pointerSlot);
      return;
    }

    if (_widgetDropPreviewPointerSlot == pointerSlot &&
        _widgetDropPreviewAnchorSlot == anchorSlot &&
        _widgetDropPreviewSpanX == spanX &&
        _widgetDropPreviewSpanY == spanY) {
      return;
    }

    setState(() {
      _widgetDropPreviewPointerSlot = pointerSlot;
      _widgetDropPreviewAnchorSlot = anchorSlot;
      _widgetDropPreviewSpanX = spanX;
      _widgetDropPreviewSpanY = spanY;
    });
  }

  void _normalizePersistedWidgetSpans() {
    for (final entry in widget.page.slots.entries) {
      final slot = entry.key;
      final content = entry.value;
      switch (content) {
        case WidgetSlot(widget: final launcherWidget):
          final (spanX, spanY) = _effectiveSpanForContent(content);
          if (launcherWidget.spanX == spanX && launcherWidget.spanY == spanY) {
            continue;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                widget.pageIndex >=
                    context.read<WorkspaceCubit>().state.pages.length) {
              return;
            }
            final liveContent = context
                .read<WorkspaceCubit>()
                .state
                .pages[widget.pageIndex]
                .slots[slot];
            if (liveContent is! WidgetSlot) return;
            final (liveSpanX, liveSpanY) =
                _effectiveSpanForContent(liveContent);
            if (liveContent.widget.spanX == liveSpanX &&
                liveContent.widget.spanY == liveSpanY) {
              return;
            }
            context.read<WorkspaceCubit>().updateWidgetSpan(
                  widget.pageIndex,
                  slot,
                  liveContent.widget.copyWith(
                    spanX: liveSpanX,
                    spanY: liveSpanY,
                  ),
                );
          });
        case WidgetStackSlot(:final spanX, :final spanY):
          final (effectiveSpanX, effectiveSpanY) =
              _effectiveSpanForContent(content);
          if (spanX == effectiveSpanX && spanY == effectiveSpanY) continue;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                widget.pageIndex >=
                    context.read<WorkspaceCubit>().state.pages.length) {
              return;
            }
            final liveContent = context
                .read<WorkspaceCubit>()
                .state
                .pages[widget.pageIndex]
                .slots[slot];
            if (liveContent is! WidgetStackSlot) return;
            final (liveSpanX, liveSpanY) =
                _effectiveSpanForContent(liveContent);
            if (liveContent.spanX == liveSpanX &&
                liveContent.spanY == liveSpanY) {
              return;
            }
            context.read<WorkspaceCubit>().updateWidgetStackSpan(
                  widget.pageIndex,
                  slot,
                  liveSpanX,
                  liveSpanY,
                );
          });
        default:
          break;
      }
    }
  }

  (int, int) _effectiveSpanForContent(SlotContent? content) {
    switch (content) {
      case WidgetSlot(:final widget):
        final minSpanX = _minSpanXForWidget(widget);
        final minSpanY = _minSpanYForWidget(widget);
        final maxSpanX = _maxSpanXForWidget(widget, minSpanX: minSpanX);
        final maxSpanY = _maxSpanYForWidget(widget, minSpanY: minSpanY);
        return (
          widget.spanX.clamp(minSpanX, maxSpanX).toInt(),
          widget.spanY.clamp(minSpanY, maxSpanY).toInt(),
        );
      case WidgetStackSlot(:final widgets, :final spanX, :final spanY):
        if (widgets.isEmpty) return (0, 0);
        return (
          spanX.clamp(1, widget.settings.gridColumns).toInt(),
          spanY.clamp(1, widget.settings.gridRows).toInt(),
        );
      default:
        return (0, 0);
    }
  }

  Set<int> _occupiedWidgetSlots(
    WorkspacePage page,
    int columns,
    int rows, {
    int? ignoreAnchorSlot,
  }) {
    // Fast path: build() and the drag hit-tests hit this with no
    // ignoreAnchorSlot every frame. Return the cached set when nothing
    // has changed since last compute.
    if (ignoreAnchorSlot == null &&
        identical(_occupiedMemoPage, page) &&
        _occupiedMemoCols == columns &&
        _occupiedMemoRows == rows &&
        _occupiedMemoResult != null) {
      return _occupiedMemoResult!;
    }

    final occupied = <int>{};
    for (final entry in page.slots.entries) {
      if (entry.key == ignoreAnchorSlot) continue;
      final (spanX, spanY) = _effectiveSpanForContent(entry.value);
      if (spanX == 0 || spanY == 0) continue;
      final covered = slotsForSpan(entry.key, spanX, spanY, columns, rows);
      if (covered != null) occupied.addAll(covered);
    }

    if (ignoreAnchorSlot == null) {
      _occupiedMemoPage = page;
      _occupiedMemoCols = columns;
      _occupiedMemoRows = rows;
      _occupiedMemoResult = occupied;
    }
    return occupied;
  }

  Set<int> _currentWidgetCoverage(
    WorkspacePage page,
    int anchorSlot,
    int columns,
    int rows,
  ) {
    final (spanX, spanY) = _effectiveSpanForContent(page.slots[anchorSlot]);
    if (spanX == 0 || spanY == 0) return const <int>{};
    return {...?slotsForSpan(anchorSlot, spanX, spanY, columns, rows)};
  }

  bool _canPlaceWidgetAt(
    WorkspacePage page,
    int anchorSlot,
    int spanX,
    int spanY,
    int columns,
    int rows, {
    int? ignoreAnchorSlot,
  }) {
    final covered = slotsForSpan(anchorSlot, spanX, spanY, columns, rows);
    if (covered == null) return false;

    final ignoredCoverage = ignoreAnchorSlot == null
        ? const <int>{}
        : _currentWidgetCoverage(page, ignoreAnchorSlot, columns, rows);
    final occupiedByWidgets = _occupiedWidgetSlots(
      page,
      columns,
      rows,
      ignoreAnchorSlot: ignoreAnchorSlot,
    );

    for (final slot in covered) {
      if (occupiedByWidgets.contains(slot)) return false;
      if (ignoredCoverage.contains(slot)) continue;

      final content = page.slots[slot];
      if (content != null && content is! EmptySlot) {
        return false;
      }
    }

    return true;
  }

  int? _resolveWidgetAnchorSlot({
    required DragPayload payload,
    required int pointerSlot,
    required int spanX,
    required int spanY,
    required WorkspaceCubit workspace,
  }) {
    final cols = widget.settings.gridColumns;
    final rows = widget.settings.gridRows;
    final pointerCol = pointerSlot % cols;
    final pointerRow = pointerSlot ~/ cols;
    final ignoreSource =
        payload.sourcePage == widget.pageIndex ? payload.sourceSlot : null;
    final targetPage =
        widget.pageIndex >= 0 && widget.pageIndex < workspace.state.pages.length
            ? workspace.state.pages[widget.pageIndex]
            : widget.page;

    final desiredAnchorCol =
        (pointerCol - spanX ~/ 2).clamp(0, cols - spanX).toInt();
    final desiredAnchorRow =
        (pointerRow - spanY ~/ 2).clamp(0, rows - spanY).toInt();
    final candidates = <({int slot, int distance})>[];
    for (int anchorRow = 0; anchorRow <= rows - spanY; anchorRow++) {
      for (int anchorCol = 0; anchorCol <= cols - spanX; anchorCol++) {
        final distanceX = anchorCol - desiredAnchorCol;
        final distanceY = anchorRow - desiredAnchorRow;
        candidates.add((
          slot: anchorRow * cols + anchorCol,
          distance: distanceX * distanceX + distanceY * distanceY,
        ));
      }
    }
    candidates.sort((a, b) => a.distance.compareTo(b.distance));

    for (final candidate in candidates) {
      final anchorSlot = candidate.slot;
      if (payload.sourcePage == widget.pageIndex &&
          payload.sourceSlot == anchorSlot) {
        continue;
      }

      final target = targetPage.slots[anchorSlot];
      if (target is WidgetSlot || target is WidgetStackSlot) {
        return anchorSlot;
      }
      if (target is FolderSlot) continue;
      if (target is AppSlot) {
        final path = _findDisplacementPath(
          anchorSlot,
          cols,
          rows,
          ignoreSlot: ignoreSource,
        );
        if (path != null) return anchorSlot;
        continue;
      }

      if (_canPlaceWidgetAllowingAppDisplacement(
        anchorSlot: anchorSlot,
        spanX: spanX,
        spanY: spanY,
        ignoreAnchorSlot: ignoreSource,
      )) {
        return anchorSlot;
      }
    }

    return null;
  }

  Widget? _buildWidgetDropPreview(double cellWidth, double cellHeight) {
    if (!(widget.dragController.activeDrag?.isWidget ?? false)) return null;
    final anchorSlot = _widgetDropPreviewAnchorSlot;
    if (anchorSlot == null) return null;

    final safeSpanX =
        _widgetDropPreviewSpanX.clamp(1, widget.settings.gridColumns).toInt();
    final safeSpanY =
        _widgetDropPreviewSpanY.clamp(1, widget.settings.gridRows).toInt();
    final rect = _slotRect(anchorSlot, cellWidth, cellHeight);

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: cellWidth * safeSpanX + _gridGap * (safeSpanX - 1),
      height: cellHeight * safeSpanY + _gridGap * (safeSpanY - 1),
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.55),
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncSelectionGuard();
    final totalSlots = widget.settings.gridColumns * widget.settings.gridRows;
    final coveredSlots = _occupiedWidgetSlots(
      widget.page,
      widget.settings.gridColumns,
      widget.settings.gridRows,
    );
    final selectedContent = _selectedWidgetSlot == null
        ? null
        : widget.page.slots[_selectedWidgetSlot!];
    if (_selectedWidgetSlot != null &&
        selectedContent is! WidgetSlot &&
        selectedContent is! WidgetStackSlot) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _clearWidgetResizeSelection();
      });
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = widget.settings.gridColumns;
          final rows = widget.settings.gridRows;
          final cellWidth =
              (constraints.maxWidth - (columns - 1) * _gridGap) / columns;
          final cellHeight =
              (constraints.maxHeight - (rows - 1) * _gridGap) / rows;
          // Keep instance copies so helpers called from onMove/onDrop can use them.
          _cellWidth = cellWidth;
          _cellHeight = cellHeight;
          // Only schedule a metadata refresh when cell dimensions actually
          // change — not on every PageView scroll frame.
          // PERF: skip the widget-metadata refresh entirely while the drawer
          // is active. The refresh fires a slow AppWidgetManager IPC binder
          // call (100-200ms platform-thread stall), and every drawer route
          // push/pop shifts layout constraints enough to trip the dimension
          // check. The workspace isn't visible during drawer interaction, so
          // there's nothing to refresh for. Pending refreshes are deferred
          // until the next LayoutBuilder pass after the drawer closes.
          final cwRounded = cellWidth.roundToDouble();
          final chRounded = cellHeight.roundToDouble();
          final drawerActive = context.read<AppsCubit>().drawerActive;
          if (!drawerActive &&
              (_lastRefreshedCellWidth != cwRounded ||
                  _lastRefreshedCellHeight != chRounded)) {
            _lastRefreshedCellWidth = cwRounded;
            _lastRefreshedCellHeight = chRounded;
            _widgetMetadataRefreshDebounce?.cancel();
            _widgetMetadataRefreshDebounce = Timer(
              _widgetMetadataRefreshDelay,
              () {
                if (mounted) _refreshWorkspaceWidgetMetadata();
              },
            );
          }

          return Stack(
            key: _stackKey,
            clipBehavior: Clip.none,
            children: [
              // Page-wide dismiss catcher behind the widgets. When nothing is
              // selected we only register a tap recognizer so it can't compete
              // with the PageView's horizontal drag recognizer in the arena
              // (a pan recognizer here at the default ~18px slop would tie
              // with PageView and sometimes win, breaking paging).
              //
              // When a widget IS selected we swap in an eager pan recognizer
              // with an 8px slop. That beats PageView's ~18px slop in the
              // gesture arena, so any swipe — left/right/up/down, over the
              // widget or over empty space on the page — dismisses the
              // selection before PageView can claim the gesture. This is the
              // structural guarantee behind "edit mode blocks all swipe
              // actions until dismissed"; the WidgetResizeGestureGuard +
              // NeverScrollableScrollPhysics path is defense-in-depth on top.
              Positioned.fill(
                child: _selectedWidgetSlot == null
                    ? RawGestureDetector(
                        behavior: HitTestBehavior.translucent,
                        gestures: <Type, GestureRecognizerFactory>{
                          TapGestureRecognizer:
                              GestureRecognizerFactoryWithHandlers<
                                  TapGestureRecognizer>(
                            () => TapGestureRecognizer(),
                            (r) => r.onTap = _clearWidgetResizeSelection,
                          ),
                          _WidgetEdgeLongPressGestureRecognizer:
                              GestureRecognizerFactoryWithHandlers<
                                  _WidgetEdgeLongPressGestureRecognizer>(
                            () => _WidgetEdgeLongPressGestureRecognizer(),
                            (r) => r.onLongPressStart =
                                (details) => _handleBackgroundLongPressStart(
                                      details,
                                      cellWidth,
                                      cellHeight,
                                    ),
                          ),
                        },
                      )
                    : RawGestureDetector(
                        behavior: HitTestBehavior.translucent,
                        gestures: <Type, GestureRecognizerFactory>{
                          TapGestureRecognizer:
                              GestureRecognizerFactoryWithHandlers<
                                  TapGestureRecognizer>(
                            () => TapGestureRecognizer(),
                            (r) => r.onTap = _clearWidgetResizeSelection,
                          ),
                          LongPressGestureRecognizer:
                              GestureRecognizerFactoryWithHandlers<
                                  LongPressGestureRecognizer>(
                            () => LongPressGestureRecognizer(),
                            (r) => r.onLongPress = _openBackgroundEditMenu,
                          ),
                          _EagerDismissPanGestureRecognizer:
                              GestureRecognizerFactoryWithHandlers<
                                  _EagerDismissPanGestureRecognizer>(
                            () => _EagerDismissPanGestureRecognizer(),
                            (r) => r.onStart =
                                (_) => _clearWidgetResizeSelection(),
                          ),
                        },
                      ),
              ),
              if (widget.settings.showGridDebugOverlay)
                ...List.generate(totalSlots, (slot) {
                  final content = widget.page.slots[slot];
                  final isWidgetAnchor =
                      content is WidgetSlot || content is WidgetStackSlot;
                  final isCoveredByWidget =
                      coveredSlots.contains(slot) && !isWidgetAnchor;
                  final isEmpty = !isCoveredByWidget &&
                      (content == null || content is EmptySlot);
                  final rect = _slotRect(slot, cellWidth, cellHeight);

                  return Positioned(
                    left: rect.left,
                    top: rect.top,
                    width: rect.width,
                    height: rect.height,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isEmpty
                              ? Colors.green.withValues(alpha: 0.14)
                              : Colors.red.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isEmpty
                                ? Colors.greenAccent.withValues(alpha: 0.9)
                                : Colors.redAccent.withValues(alpha: 0.9),
                          ),
                        ),
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          '$slot',
                          style: TextStyle(
                            color: isEmpty
                                ? Colors.greenAccent.shade100
                                : Colors.redAccent.shade100,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              for (int slot = 0; slot < totalSlots; slot++)
                ..._buildPositionedContent(
                  context,
                  slot,
                  coveredSlots,
                  cellWidth,
                  cellHeight,
                ),
              ListenableBuilder(
                listenable: widget.dragController,
                builder: (context, _) {
                  if (!widget.dragController.isDragging) {
                    return const SizedBox.shrink();
                  }

                  final workspace = context.read<WorkspaceCubit>();
                  // When dragging a widget, its own coverage slots will be
                  // freed on drop and must still receive DragTargets so the
                  // widget can be moved to partially-overlapping positions.
                  final sourceWidgetCoverage =
                      _sourceWidgetCoverage(widget.dragController.activeDrag);
                  final isWidgetDrag =
                      widget.dragController.activeDrag?.isWidget ?? false;
                  final widgetDropPreview =
                      _buildWidgetDropPreview(cellWidth, cellHeight);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (widgetDropPreview != null) widgetDropPreview,
                      ...List.generate(totalSlots, (slot) {
                        final content = widget.page.slots[slot];
                        final isWidgetAnchor =
                            content is WidgetSlot || content is WidgetStackSlot;
                        final coveredByOtherWidget =
                            coveredSlots.contains(slot) &&
                                !isWidgetAnchor &&
                                !sourceWidgetCoverage.contains(slot);
                        if (coveredByOtherWidget && isWidgetDrag) {
                          return const SizedBox.shrink();
                        }

                        final rect = _slotRect(slot, cellWidth, cellHeight);
                        return Positioned(
                          left: rect.left,
                          top: rect.top,
                          width: rect.width,
                          height: rect.height,
                          child: DragTarget<DragPayload>(
                            onWillAcceptWithDetails: (d) {
                              final accepted =
                                  _willAccept(d.data, content, slot, workspace);
                              if (d.data.isWidget && accepted) {
                                _updateWidgetDropPreview(
                                  d.data,
                                  slot,
                                  workspace,
                                );
                              }
                              return accepted;
                            },
                            onAcceptWithDetails: (d) =>
                                _onDrop(context, d, slot),
                            onMove: (details) {
                              final isSourceSlot =
                                  details.data.sourcePage == widget.pageIndex &&
                                      details.data.sourceSlot == slot;
                              if (isSourceSlot) return;

                              if (details.data.isWidget) {
                                _updateWidgetDropPreview(
                                  details.data,
                                  slot,
                                  workspace,
                                );
                                if (content is AppSlot) {
                                  final settings =
                                      context.read<SettingsCubit>().state;
                                  _startDisplacementTimer(
                                      slot, workspace, settings);
                                }
                              } else if (content is AppSlot) {
                                // Compute how much of the tile the dragged icon covers.
                                final localPos =
                                    _localPositionInSlot(details.offset, slot);
                                if (localPos != null) {
                                  final overlap = _overlapFraction(localPos);
                                  if (overlap >= 0.25) {
                                    // Deep hover → folder creation mode
                                    _cancelDisplacementTimer(slot);
                                    if (!_folderPreviewSlots.contains(slot)) {
                                      setState(
                                          () => _folderPreviewSlots.add(slot));
                                    }
                                    return;
                                  }
                                }
                                // Shallow hover → displacement mode
                                if (_folderPreviewSlots.contains(slot)) {
                                  setState(
                                      () => _folderPreviewSlots.remove(slot));
                                }
                                final settings =
                                    context.read<SettingsCubit>().state;
                                final pushDir = localPos != null
                                    ? _pushDirectionFromLocalPos(localPos)
                                    : Offset.zero;
                                _startDisplacementTimer(
                                    slot, workspace, settings,
                                    withPreview: true,
                                    preferredDirection: pushDir);
                              } else if (content is FolderSlot) {
                                final settings =
                                    context.read<SettingsCubit>().state;
                                _startDisplacementTimer(
                                    slot, workspace, settings,
                                    withPreview: true);
                              }
                            },
                            onLeave: (payload) {
                              _cancelDisplacementTimer(slot);
                              if (payload?.isWidget ?? false) {
                                _clearWidgetDropPreview(slot);
                              }
                            },
                            builder: (context, candidateData, rejectData) {
                              final isHovered = candidateData.isNotEmpty;
                              final isRejected = rejectData.isNotEmpty;
                              final isGhost =
                                  _ghostDestinationSlots.contains(slot);
                              final isFolderPreview =
                                  _folderPreviewSlots.contains(slot);
                              final hoveredPayload =
                                  isHovered ? candidateData.first : null;
                              final isHoveredWidget =
                                  hoveredPayload?.isWidget ?? false;
                              if (isRejected) {
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 100),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                );
                              }
                              if (isHoveredWidget) {
                                return const SizedBox.shrink();
                              }
                              if (isFolderPreview) {
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.orange.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color:
                                          Colors.orange.withValues(alpha: 0.8),
                                      width: 1.5,
                                    ),
                                  ),
                                );
                              }
                              if (isGhost && !isHovered) {
                                return IgnorePointer(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.35),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                decoration: isHovered
                                    ? BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                        border:
                                            Border.all(color: Colors.white24),
                                      )
                                    : null,
                              );
                            },
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
              if (!widget.dragController.isDragging)
                ..._buildSelectedWidgetResizeFrame(cellWidth, cellHeight),
              if (!widget.dragController.isDragging)
                ..._buildSelectedWidgetActionMenu(
                  cellWidth,
                  cellHeight,
                  constraints.maxWidth,
                  constraints.maxHeight,
                ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildSelectedWidgetResizeFrame(
    double cellWidth,
    double cellHeight,
  ) {
    final slot = _selectedWidgetSlot;
    if (slot == null) return const [];
    final content = widget.page.slots[slot];
    final (spanX, spanY) = _effectiveSpanForContent(content);
    if (spanX <= 0 || spanY <= 0) return const [];

    final safeSpanX = spanX.clamp(1, widget.settings.gridColumns).toInt();
    final safeSpanY = spanY.clamp(1, widget.settings.gridRows).toInt();
    final rect = _slotRect(slot, cellWidth, cellHeight);
    final width = cellWidth * safeSpanX + _gridGap * (safeSpanX - 1);
    final height = cellHeight * safeSpanY + _gridGap * (safeSpanY - 1);
    const resizeTouchOutset = _WorkspaceWidgetResizeFrame.touchOutset;

    return [
      Positioned(
        left: rect.left - resizeTouchOutset,
        top: rect.top - resizeTouchOutset,
        width: width + resizeTouchOutset * 2,
        height: height + resizeTouchOutset * 2,
        child: _WorkspaceWidgetResizeFrame(
          contentOutset: resizeTouchOutset,
          stepX: cellWidth + _gridGap,
          stepY: cellHeight + _gridGap,
          showDebugHitZones: widget.settings.showGridDebugOverlay,
          onDismiss: _clearWidgetResizeSelection,
          onResizeSteps: _resizeSelectedWidgetBySteps,
        ),
      ),
    ];
  }

  List<Widget> _buildSelectedWidgetActionMenu(
    double cellWidth,
    double cellHeight,
    double viewportWidth,
    double viewportHeight,
  ) {
    if (_menuHiddenForGesture) return const [];
    final slot = _selectedWidgetSlot;
    if (slot == null) return const [];
    final content = widget.page.slots[slot];
    if (content == null) return const [];
    if (content is! WidgetSlot && content is! WidgetStackSlot) {
      return const [];
    }
    final (spanX, spanY) = _effectiveSpanForContent(content);
    if (spanX <= 0 || spanY <= 0) return const [];

    final safeSpanX = spanX.clamp(1, widget.settings.gridColumns).toInt();
    final safeSpanY = spanY.clamp(1, widget.settings.gridRows).toInt();
    final rect = _slotRect(slot, cellWidth, cellHeight);
    final widgetWidth = cellWidth * safeSpanX + _gridGap * (safeSpanX - 1);
    final widgetHeight = cellHeight * safeSpanY + _gridGap * (safeSpanY - 1);

    const menuVerticalGap = 8.0;
    const estimatedMenuHeight = 58.0;
    const minMenuWidth = 180.0;
    const maxMenuWidth = 280.0;
    final menuWidth = widgetWidth
        .clamp(minMenuWidth, math.min(maxMenuWidth, viewportWidth))
        .toDouble();

    // Prefer above the widget; if there's no room above, try below; if neither
    // fits (widget fills the viewport) overlay just inside the top edge so the
    // menu always stays on-screen.
    final fitsAbove = rect.top >= estimatedMenuHeight + menuVerticalGap;
    final fitsBelow =
        rect.top + widgetHeight + estimatedMenuHeight + menuVerticalGap <=
            viewportHeight;
    double menuTop;
    if (fitsAbove) {
      menuTop = rect.top - estimatedMenuHeight - menuVerticalGap;
    } else if (fitsBelow) {
      menuTop = rect.top + widgetHeight + menuVerticalGap;
    } else {
      menuTop = rect.top + menuVerticalGap;
    }
    menuTop = menuTop
        .clamp(0.0, math.max(0.0, viewportHeight - estimatedMenuHeight))
        .toDouble();

    final rawMenuLeft = rect.left + (widgetWidth - menuWidth) / 2;
    final menuLeft = rawMenuLeft
        .clamp(0.0, math.max(0.0, viewportWidth - menuWidth))
        .toDouble();

    final isStack = content is WidgetStackSlot;

    return [
      Positioned(
        left: menuLeft,
        top: menuTop,
        width: menuWidth,
        child: _WidgetActionMenu(
          isStack: isStack,
          onInfo: () => _openSelectedWidgetInfo(content),
          onCreateOrEditStack: isStack
              ? () => _openStackEditOverlay(
                    slot,
                    content,
                    cellWidth,
                    cellHeight,
                  )
              : _pickWidgetForNewStack,
          onRemove: _removeSelectedWidget,
        ),
      ),
    ];
  }

  void _openSelectedWidgetInfo(SlotContent content) {
    // Placeholder — the app info / widget settings sheet isn't wired yet.
    // Surfacing a SnackBar keeps the affordance discoverable until we ship
    // the real sheet.
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Widget info coming soon'),
        duration: Duration(milliseconds: 1200),
      ),
    );
  }

  void _pickWidgetForNewStack() {
    final slot = _selectedWidgetSlot;
    if (slot == null) return;
    final pick = widget.onPickWidgetForStack;
    if (pick == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Widget picker not available'),
          duration: Duration(milliseconds: 1200),
        ),
      );
      return;
    }
    // Dismiss the selection so the workspace returns to its normal state
    // before the picker route is pushed.
    final page = widget.pageIndex;
    _clearWidgetResizeSelection();
    pick(page, slot);
  }

  Future<void> _openStackEditOverlay(
    int slot,
    WidgetStackSlot stack,
    double cellWidth,
    double cellHeight,
  ) async {
    final workspace = context.read<WorkspaceCubit>();
    final pageIndex = widget.pageIndex;
    final pick = widget.onPickWidgetForStack;
    // Dismiss selection so the resize frame doesn't sit behind the overlay.
    _clearWidgetResizeSelection();
    // Free the home rendering's appWidgetIds so the overlay can mount its
    // own AndroidViews for the same widgets.
    HomeWidgetStackView.suppressedAt.value = (pageIndex, slot);
    final action = await Navigator.of(context).push<_StackEditAction>(
      PageRouteBuilder<_StackEditAction>(
        opaque: false,
        // Light scrim only — the wallpaper must remain visible behind the
        // overlay (the frosted-glass card supplies its own backdrop blur).
        barrierColor: Colors.black.withValues(alpha: 0.28),
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (routeCtx, animation, _) {
          return BlocBuilder<WorkspaceCubit, WorkspaceState>(
            bloc: workspace,
            builder: (context, state) {
              final liveContent =
                  pageIndex >= 0 && pageIndex < state.pages.length
                      ? state.pages[pageIndex].slots[slot]
                      : null;
              if (liveContent is! WidgetStackSlot) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (routeCtx.mounted) Navigator.of(routeCtx).maybePop();
                });
                return const SizedBox.shrink();
              }
              return _StackEditOverlay(
                stack: liveContent,
                cellWidth: cellWidth,
                cellHeight: cellHeight,
                gap: _gridGap,
                gridColumns: widget.settings.gridColumns,
                gridRows: widget.settings.gridRows,
                canAddWidget: pick != null,
                onRemoveAt: (index) {
                  workspace.removeWidgetFromStack(
                    pageIndex,
                    slot,
                    index,
                    collapseSingle: false,
                  );
                },
                onAddWidget: () =>
                    Navigator.of(routeCtx).pop(_StackEditAction.addWidget),
                onDismiss: () => Navigator.of(routeCtx).pop(),
              );
            },
          );
        },
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
    HomeWidgetStackView.suppressedAt.value = null;
    if (!mounted) return;
    if (action == _StackEditAction.addWidget && pick != null) {
      pick(pageIndex, slot);
    }
  }

  void _removeSelectedWidget() {
    final slot = _selectedWidgetSlot;
    if (slot == null) return;
    context.read<WorkspaceCubit>().removeItem(widget.pageIndex, slot);
    _clearWidgetResizeSelection();
  }

  List<Widget> _buildPositionedContent(
    BuildContext context,
    int slot,
    Set<int> coveredSlots,
    double cellWidth,
    double cellHeight,
  ) {
    final content = widget.page.slots[slot];
    final isCoveredByAnotherWidget = coveredSlots.contains(slot) &&
        content is! WidgetSlot &&
        content is! WidgetStackSlot;
    if (content == null || content is EmptySlot) return const [];
    if (isCoveredByAnotherWidget &&
        content is! AppSlot &&
        content is! FolderSlot) {
      return const [];
    }

    if (content is WidgetSlot) {
      final (spanX, spanY) = _effectiveSpanForContent(content);
      return [
        _positionedForSpan(
          slot,
          spanX,
          spanY,
          cellWidth,
          cellHeight,
          _buildWidgetSlot(
            context,
            content,
            slot,
            resizeStepX: cellWidth + _gridGap,
            resizeStepY: cellHeight + _gridGap,
          ),
        ),
      ];
    }

    if (content is WidgetStackSlot) {
      final (spanX, spanY) = _effectiveSpanForContent(content);
      return [
        _positionedForSpan(
          slot,
          spanX,
          spanY,
          cellWidth,
          cellHeight,
          _buildWidgetStackSlot(
            context,
            content,
            slot,
            resizeStepX: cellWidth + _gridGap,
            resizeStepY: cellHeight + _gridGap,
          ),
        ),
      ];
    }

    final previewCtrl = _displacementPreviewControllers[slot];
    final previewDir = _displacementPreviewDirections[slot];
    Widget slotWidget = _buildSlotContent(context, content, slot);
    if (previewCtrl != null && previewDir != null) {
      slotWidget = AnimatedBuilder(
        animation: previewCtrl,
        builder: (ctx, child) => Transform.translate(
          offset: Offset(
            previewDir.dx * cellWidth * 0.35 * previewCtrl.value,
            previewDir.dy * cellHeight * 0.35 * previewCtrl.value,
          ),
          child: child,
        ),
        child: slotWidget,
      );
    }
    return [
      Positioned(
        left: _slotRect(slot, cellWidth, cellHeight).left,
        top: _slotRect(slot, cellWidth, cellHeight).top,
        width: cellWidth,
        height: cellHeight,
        child: slotWidget,
      ),
    ];
  }

  Positioned _positionedForSpan(
    int slot,
    int spanX,
    int spanY,
    double cellWidth,
    double cellHeight,
    Widget child,
  ) {
    final rect = _slotRect(slot, cellWidth, cellHeight);
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: cellWidth * spanX + _gridGap * (spanX - 1),
      height: cellHeight * spanY + _gridGap * (spanY - 1),
      child: child,
    );
  }

  Rect _slotRect(int slot, double cellWidth, double cellHeight) {
    final column = slot % widget.settings.gridColumns;
    final row = slot ~/ widget.settings.gridColumns;
    return Rect.fromLTWH(
      column * (cellWidth + _gridGap),
      row * (cellHeight + _gridGap),
      cellWidth,
      cellHeight,
    );
  }

  int? _widgetSlotNearPoint(
    Offset localPosition,
    double cellWidth,
    double cellHeight,
  ) {
    final gridWidth = cellWidth * widget.settings.gridColumns +
        _gridGap * (widget.settings.gridColumns - 1);
    final gridHeight = cellHeight * widget.settings.gridRows +
        _gridGap * (widget.settings.gridRows - 1);
    final gridBounds = Rect.fromLTWH(0, 0, gridWidth, gridHeight);
    int? closestSlot;
    var closestDistance = double.infinity;

    for (final entry in widget.page.slots.entries) {
      final content = entry.value;
      if (content is! WidgetSlot && content is! WidgetStackSlot) continue;

      final (spanX, spanY) = _effectiveSpanForContent(content);
      if (spanX <= 0 || spanY <= 0) continue;

      final slotRect = _slotRect(entry.key, cellWidth, cellHeight);
      final widgetRect = Rect.fromLTWH(
        slotRect.left,
        slotRect.top,
        cellWidth * spanX + _gridGap * (spanX - 1),
        cellHeight * spanY + _gridGap * (spanY - 1),
      );
      final expandedRect =
          widgetRect.inflate(_widgetLongPressHitOutset).intersect(gridBounds);
      if (!expandedRect.contains(localPosition)) continue;

      final dx = localPosition.dx < widgetRect.left
          ? widgetRect.left - localPosition.dx
          : localPosition.dx > widgetRect.right
              ? localPosition.dx - widgetRect.right
              : 0.0;
      final dy = localPosition.dy < widgetRect.top
          ? widgetRect.top - localPosition.dy
          : localPosition.dy > widgetRect.bottom
              ? localPosition.dy - widgetRect.bottom
              : 0.0;
      final distance = dx * dx + dy * dy;
      if (distance < closestDistance) {
        closestDistance = distance;
        closestSlot = entry.key;
      }
    }

    return closestSlot;
  }

  Widget _buildSlotContent(
    BuildContext context,
    SlotContent? content,
    int slot,
  ) {
    if (content == null || content is EmptySlot) {
      return const SizedBox.shrink();
    }

    if (content is WidgetSlot) {
      return _buildWidgetSlot(context, content, slot);
    }

    if (content is WidgetStackSlot) {
      return _buildWidgetStackSlot(context, content, slot);
    }

    if (content is AppSlot) {
      return _buildAppSlot(context, content, slot);
    }

    if (content is FolderSlot) {
      return _buildFolderSlot(context, content, slot);
    }

    return const SizedBox.shrink();
  }

  Widget _buildWidgetSlot(
    BuildContext context,
    WidgetSlot content,
    int slot, {
    double resizeStepX = 110,
    double resizeStepY = 110,
  }) {
    final w = content.widget;
    final minSpanX = _minSpanXForWidget(w);
    final minSpanY = _minSpanYForWidget(w);
    final maxSpanX = _maxSpanXForWidget(w, minSpanX: minSpanX);
    final maxSpanY = _maxSpanYForWidget(w, minSpanY: minSpanY);
    final (effectiveSpanX, effectiveSpanY) = _effectiveSpanForContent(content);
    final payload = DragPayload(
      item: WorkspaceItemInfo(
        id: w.id,
        itemType: ItemType.appWidget,
        packageName: w.providerPackage,
        componentName: w.providerClass,
        title: 'Widget',
        spanX: effectiveSpanX,
        spanY: effectiveSpanY,
      ),
      sourcePage: widget.pageIndex,
      sourceSlot: slot,
    );
    final isSelected = _selectedWidgetSlot == slot;
    final widgetView = HomeWidgetSlot(
      widget: w,
      page: widget.pageIndex,
      slot: slot,
      minSpanX: minSpanX,
      minSpanY: minSpanY,
      maxSpanX: maxSpanX,
      maxSpanY: maxSpanY,
      gridColumns: widget.settings.gridColumns,
      gridRows: widget.settings.gridRows,
      resizeStepX: resizeStepX,
      resizeStepY: resizeStepY,
      gridGap: _gridGap,
      isSelected: isSelected,
      onDismissResize: _clearWidgetResizeSelection,
      onResize: (nextSlot, nextSpanX, nextSpanY) =>
          _resizeWidget(slot, w, nextSlot, nextSpanX, nextSpanY),
    );

    return LongPressDraggable<DragPayload>(
      data: payload,
      rootOverlay: true,
      dragAnchorStrategy: _centerDragAnchorStrategy,
      delay: const Duration(milliseconds: 350),
      onDragStarted: () => _armWidgetDrag(slot),
      onDragUpdate: (details) => _maybeActivateWidgetDrag(
        details,
        payload,
        slot,
      ),
      onDragEnd: (details) =>
          _finishWidgetDrag(slot, wasAccepted: details.wasAccepted),
      onDraggableCanceled: (_, __) =>
          _finishWidgetDrag(slot, wasAccepted: false),
      onDragCompleted: () => _completeWidgetDrag(slot),
      feedback: _buildDeferredWidgetDragFeedback(
        slot: slot,
        width: _spanDragWidth(effectiveSpanX, resizeStepX),
        height: _spanDragHeight(effectiveSpanY, resizeStepY),
        child: HomeWidgetSlot(
          widget: w,
          page: widget.pageIndex,
          slot: slot,
          minSpanX: minSpanX,
          minSpanY: minSpanY,
          maxSpanX: maxSpanX,
          maxSpanY: maxSpanY,
          gridColumns: widget.settings.gridColumns,
          gridRows: widget.settings.gridRows,
          resizeStepX: resizeStepX,
          resizeStepY: resizeStepY,
          gridGap: _gridGap,
          isSelected: false,
          onDismissResize: _clearWidgetResizeSelection,
          onResize: (nextSlot, nextSpanX, nextSpanY) =>
              _resizeWidget(slot, w, nextSlot, nextSpanX, nextSpanY),
        ),
      ),
      childWhenDragging: ValueListenableBuilder<int?>(
        valueListenable: _activeWidgetDragFeedbackSlot,
        builder: (context, activeSlot, _) {
          return AnimatedOpacity(
            opacity: activeSlot == slot ? 0.12 : 1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: HomeWidgetSlot(
              widget: w,
              page: widget.pageIndex,
              slot: slot,
              minSpanX: minSpanX,
              minSpanY: minSpanY,
              maxSpanX: maxSpanX,
              maxSpanY: maxSpanY,
              gridColumns: widget.settings.gridColumns,
              gridRows: widget.settings.gridRows,
              resizeStepX: resizeStepX,
              resizeStepY: resizeStepY,
              gridGap: _gridGap,
              isSelected: activeSlot != slot,
              onDismissResize: _clearWidgetResizeSelection,
              onResize: (nextSlot, nextSpanX, nextSpanY) =>
                  _resizeWidget(slot, w, nextSlot, nextSpanX, nextSpanY),
            ),
          );
        },
      ),
      child: widgetView,
    );
  }

  Widget _buildWidgetStackSlot(
    BuildContext context,
    WidgetStackSlot content,
    int slot, {
    double resizeStepX = 110,
    double resizeStepY = 110,
  }) {
    final minSpanX = content.widgets.fold<int>(
      1,
      (value, widget) => math.max(value, _minSpanXForWidget(widget)),
    );
    final minSpanY = content.widgets.fold<int>(
      1,
      (value, widget) => math.max(value, _minSpanYForWidget(widget)),
    );
    final maxSpanX = content.widgets.fold<int>(
      widget.settings.gridColumns,
      (value, widget) => math.min(
        value,
        _maxSpanXForWidget(
          widget,
          minSpanX: _minSpanXForWidget(widget),
        ),
      ),
    );
    final maxSpanY = content.widgets.fold<int>(
      _stackMaxRowSpan(),
      (value, widget) => math.min(
        value,
        _maxSpanYForWidget(
          widget,
          minSpanY: _minSpanYForWidget(widget),
        ),
      ),
    );
    final safeMaxSpanX = math.max(minSpanX, maxSpanX);
    final safeMaxSpanY = math.max(minSpanY, maxSpanY);
    final (effectiveSpanX, effectiveSpanY) = _effectiveSpanForContent(content);
    // Use first widget to build a representative drag payload
    final first = content.widgets.first;
    final payload = DragPayload(
      item: WorkspaceItemInfo(
        id: first.id,
        itemType: ItemType.appWidget,
        packageName: first.providerPackage,
        componentName: first.providerClass,
        title: 'Widget Stack',
        spanX: effectiveSpanX,
        spanY: effectiveSpanY,
      ),
      sourcePage: widget.pageIndex,
      sourceSlot: slot,
    );
    final isSelected = _selectedWidgetSlot == slot;
    final stackView = HomeWidgetStackView(
      widgets: content.widgets,
      spanX: content.spanX,
      spanY: content.spanY,
      page: widget.pageIndex,
      slot: slot,
      currentIndex: content.currentIndex,
      minSpanX: minSpanX,
      minSpanY: minSpanY,
      maxSpanX: safeMaxSpanX,
      maxSpanY: safeMaxSpanY,
      gridColumns: widget.settings.gridColumns,
      gridRows: widget.settings.gridRows,
      resizeStepX: resizeStepX,
      resizeStepY: resizeStepY,
      gridGap: _gridGap,
      isSelected: isSelected,
      onDismissResize: _clearWidgetResizeSelection,
      onIndexChanged: (index) => context
          .read<WorkspaceCubit>()
          .updateWidgetStackIndex(widget.pageIndex, slot, index),
      onResize: (nextSlot, nextSpanX, nextSpanY) =>
          _resizeWidgetStack(slot, content, nextSlot, nextSpanX, nextSpanY),
    );

    return LongPressDraggable<DragPayload>(
      data: payload,
      rootOverlay: true,
      dragAnchorStrategy: _centerDragAnchorStrategy,
      delay: const Duration(milliseconds: 350),
      onDragStarted: () => _armWidgetDrag(slot),
      onDragUpdate: (details) => _maybeActivateWidgetDrag(
        details,
        payload,
        slot,
      ),
      onDragEnd: (details) =>
          _finishWidgetDrag(slot, wasAccepted: details.wasAccepted),
      onDraggableCanceled: (_, __) =>
          _finishWidgetDrag(slot, wasAccepted: false),
      onDragCompleted: () => _completeWidgetDrag(slot),
      feedback: _buildDeferredWidgetDragFeedback(
        slot: slot,
        width: _spanDragWidth(effectiveSpanX, resizeStepX),
        height: _spanDragHeight(effectiveSpanY, resizeStepY),
        child: HomeWidgetStackView(
          widgets: content.widgets,
          spanX: content.spanX,
          spanY: content.spanY,
          page: widget.pageIndex,
          slot: slot,
          currentIndex: content.currentIndex,
          minSpanX: minSpanX,
          minSpanY: minSpanY,
          maxSpanX: safeMaxSpanX,
          maxSpanY: safeMaxSpanY,
          gridColumns: widget.settings.gridColumns,
          gridRows: widget.settings.gridRows,
          resizeStepX: resizeStepX,
          resizeStepY: resizeStepY,
          gridGap: _gridGap,
          isSelected: false,
          onDismissResize: _clearWidgetResizeSelection,
          onResize: (nextSlot, nextSpanX, nextSpanY) =>
              _resizeWidgetStack(slot, content, nextSlot, nextSpanX, nextSpanY),
        ),
      ),
      childWhenDragging: ValueListenableBuilder<int?>(
        valueListenable: _activeWidgetDragFeedbackSlot,
        builder: (context, activeSlot, _) {
          return AnimatedOpacity(
            opacity: activeSlot == slot ? 0.12 : 1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: HomeWidgetStackView(
              widgets: content.widgets,
              spanX: content.spanX,
              spanY: content.spanY,
              page: widget.pageIndex,
              slot: slot,
              currentIndex: content.currentIndex,
              minSpanX: minSpanX,
              minSpanY: minSpanY,
              maxSpanX: safeMaxSpanX,
              maxSpanY: safeMaxSpanY,
              gridColumns: widget.settings.gridColumns,
              gridRows: widget.settings.gridRows,
              resizeStepX: resizeStepX,
              resizeStepY: resizeStepY,
              gridGap: _gridGap,
              isSelected: activeSlot != slot,
              onDismissResize: _clearWidgetResizeSelection,
              onResize: (nextSlot, nextSpanX, nextSpanY) => _resizeWidgetStack(
                  slot, content, nextSlot, nextSpanX, nextSpanY),
            ),
          );
        },
      ),
      child: stackView,
    );
  }

  double _spanDragWidth(int spanX, double resizeStepX) {
    final clampedSpan = spanX.clamp(1, widget.settings.gridColumns);
    return resizeStepX * clampedSpan - _gridGap;
  }

  double _spanDragHeight(int spanY, double resizeStepY) {
    final clampedSpan = spanY.clamp(1, widget.settings.gridRows);
    return resizeStepY * clampedSpan - _gridGap;
  }

  Widget _buildDeferredWidgetDragFeedback({
    required int slot,
    required double width,
    required double height,
    required Widget child,
  }) {
    return ValueListenableBuilder<int?>(
      valueListenable: _activeWidgetDragFeedbackSlot,
      builder: (context, activeSlot, _) {
        if (activeSlot != slot) {
          return SizedBox(width: width, height: height);
        }

        return _buildWidgetDragFeedback(
          width: width,
          height: height,
          child: child,
        );
      },
    );
  }

  Offset _centerDragAnchorStrategy(
    Draggable<Object> draggable,
    BuildContext context,
    Offset position,
  ) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? Offset.zero : box.size.center(Offset.zero);
  }

  Widget _buildWidgetDragFeedback({
    required double width,
    required double height,
    required Widget child,
  }) {
    return PickupFeedback(
      peakScale: 1.1,
      targetScale: 1.0,
      opacity: 0.92,
      child: SizedBox(
        width: width,
        height: height,
        child: IgnorePointer(
          child: Opacity(
            opacity: 1.0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.34),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    Positioned.fill(child: child),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.92),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppSlot(BuildContext context, AppSlot content, int slot) {
    final item = content.item;
    // BlocSelector subscribes only this leaf to AppsCubit's apps list (O(1)
    // map lookup, not an O(N) scan). Badge updates flow through BadgeStore
    // instead of Bloc state, so a notification on one app doesn't run a
    // selector on every other tile on the page.
    return Center(
      child: BlocSelector<AppsCubit, AppsState, AppInfo?>(
        selector: (state) => state.appsByPackage[item.packageName],
        builder: (context, liveApp) {
          final app = AppInfo(
            id: item.id,
            packageName: item.packageName,
            appComponentName: item.componentName ??
                liveApp?.appComponentName ??
                item.packageName,
            title: item.title ?? liveApp?.name,
            icon: liveApp?.icon ?? item.icon,
            iconPath: liveApp?.iconPath ?? item.iconPath,
          );
          final payload = DragPayload(
              item: item, sourcePage: widget.pageIndex, sourceSlot: slot);
          return LongPressDraggable<DragPayload>(
            data: payload,
            delay: const Duration(milliseconds: 350),
            maxSimultaneousDrags: _selectedWidgetSlot == null ? null : 0,
            onDragStarted: () {
              setState(() {
                _draggingSlot = slot;
                _selectedWidgetSlot = null;
              });
              _syncSelectionGuard();
              widget.dragController
                  .startDrag(item, widget.pageIndex, slot, Offset.zero);
            },
            onDragCompleted: () {
              setState(() => _draggingSlot = null);
            },
            onDragEnd: (_) {
              setState(() => _draggingSlot = null);
              widget.dragController.cancelDrag();
            },
            onDraggableCanceled: (_, __) {
              setState(() => _draggingSlot = null);
              widget.dragController.cancelDrag();
            },
            feedback: PickupFeedback(
              child: BubbleTextView(
                app: app,
                iconSize: widget.settings.iconSize,
                showLabel: false,
                iconShape: widget.settings.iconShape,
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.3,
              child: BadgeListener(
                packageName: item.packageName,
                builder: (_, badge) => BubbleTextView(
                  app: app,
                  iconSize: widget.settings.iconSize,
                  showLabel: widget.settings.showLabels,
                  labelSize: widget.settings.labelSize,
                  iconShape: widget.settings.iconShape,
                  badgeCount: badge,
                ),
              ),
            ),
            child: BadgeListener(
              packageName: item.packageName,
              builder: (_, badge) => BubbleTextView(
                app: app,
                iconSize: widget.settings.iconSize,
                showLabel: widget.settings.showLabels,
                labelSize: widget.settings.labelSize,
                iconShape: widget.settings.iconShape,
                badgeCount: badge,
                onTap: () {
                  if (_dismissWidgetResizeSelectionIfActive()) return;
                  widget.onAppTap(app);
                },
                onLongPress: _draggingSlot == slot
                    ? null
                    : () {
                        if (_dismissWidgetResizeSelectionIfActive()) return;
                        final box = context.findRenderObject() as RenderBox?;
                        final center = box == null
                            ? Offset.zero
                            : box.localToGlobal(Offset(
                                box.size.width / 2, box.size.height / 2));
                        widget.onAppLongPress(app, slot, center);
                      },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFolderSlot(BuildContext context, FolderSlot content, int slot) {
    final folders = context.watch<WorkspaceCubit>().state.folders;
    final folder = folders[content.folderId];
    if (folder == null) return const SizedBox.shrink();

    return Center(
      child: BlocSelector<AppsCubit, AppsState, FolderInfo>(
        selector: (state) => _resolveFolderIcons(folder, state),
        builder: (context, resolvedFolder) => LongPressDraggable<DragPayload>(
          data: DragPayload(
            item: WorkspaceItemInfo(
              id: folder.id,
              itemType: ItemType.folder,
              packageName: '',
              title: folder.folderTitle,
            ),
            sourcePage: widget.pageIndex,
            sourceSlot: slot,
          ),
          delay: const Duration(milliseconds: 350),
          onDragStarted: () {
            setState(() {
              _draggingSlot = slot;
              _selectedWidgetSlot = null;
            });
            _syncSelectionGuard();
            widget.dragController.startDrag(
                WorkspaceItemInfo(
                  id: folder.id,
                  itemType: ItemType.folder,
                  packageName: '',
                  title: folder.folderTitle,
                ),
                widget.pageIndex,
                slot,
                Offset.zero);
          },
          onDragCompleted: () {
            setState(() => _draggingSlot = null);
          },
          onDragEnd: (_) {
            setState(() => _draggingSlot = null);
            widget.dragController.cancelDrag();
          },
          onDraggableCanceled: (_, __) {
            setState(() => _draggingSlot = null);
            widget.dragController.cancelDrag();
          },
          feedback: PickupFeedback(
            child: FolderIconView(
              folder: resolvedFolder,
              settings: widget.settings,
              onTap: () {},
              onLongPress: () {},
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: FolderIconView(
              folder: resolvedFolder,
              settings: widget.settings,
              onTap: () {},
              onLongPress: () {},
            ),
          ),
          child: FolderIconView(
            folder: resolvedFolder,
            settings: widget.settings,
            badgeCount: 0,
            onTap: () {
              _clearWidgetResizeSelection();
              _openFolder(context, content.folderId, slot);
            },
            onLongPress: _draggingSlot == slot ? () {} : () {},
          ),
        ),
      ),
    );
  }

  FolderInfo _resolveFolderIcons(FolderInfo folder, AppsState appsState) {
    final resolved = folder.contents.map((item) {
      final live = appsState.apps
          .where((a) => a.packageName == item.packageName)
          .firstOrNull;
      if (live == null) return item;
      return WorkspaceItemInfo(
        id: item.id,
        itemType: item.itemType,
        packageName: item.packageName,
        componentName: item.componentName ?? live.appComponentName,
        title: item.title ?? live.name,
        icon: live.icon,
        iconPath: live.iconPath,
      );
    }).toList();
    return FolderInfo(
      id: folder.id,
      folderTitle: folder.folderTitle,
      contents: resolved,
      cellX: folder.cellX,
      cellY: folder.cellY,
      screenId: folder.screenId,
    );
  }

  void _openFolder(BuildContext context, String folderId, int slot) {
    if (_openFolderId == folderId && _openFolderEntry != null) return;
    _closeOpenFolder();
    final overlay = Overlay.of(context);
    final workspaceCubit = context.read<WorkspaceCubit>();
    final appsCubit = context.read<AppsCubit>();
    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (overlayCtx) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: workspaceCubit),
          BlocProvider.value(value: appsCubit),
        ],
        child: FolderView(
          folderId: folderId,
          folderPage: widget.pageIndex,
          folderSlot: slot,
          settings: widget.settings,
          dragController: widget.dragController,
          onClose: () {
            if (_openFolderEntry == entry) {
              _openFolderEntry = null;
              _openFolderId = null;
            }
            entry?.remove();
            entry = null;
          },
          onAppTap: (app) {
            if (_openFolderEntry == entry) {
              _openFolderEntry = null;
              _openFolderId = null;
            }
            entry?.remove();
            entry = null;
            LauncherService.launchApp(app.packageName);
          },
        ),
      ),
    );
    _openFolderEntry = entry;
    _openFolderId = folderId;
    overlay.insert(entry!);
  }

  int _minSpanXForWidget(LauncherWidgetInfo widgetInfo) {
    if (_isDefaultClockWidget(widgetInfo)) {
      return WorkspaceCubit.defaultClockMinSpanX
          .clamp(1, widget.settings.gridColumns)
          .toInt();
    }
    if (widgetInfo.minSpanX > 0) {
      final span =
          widgetInfo.minSpanX.clamp(1, widget.settings.gridColumns).toInt();
      // If the stored minSpanX fills the entire grid but the widget claims to
      // support horizontal resize, its minResizeWidth was unreasonably large —
      // allow free resize rather than blocking it entirely.
      if (span >= widget.settings.gridColumns &&
          _canResizeHorizontally(widgetInfo)) {
        widgetLog(
          '[CellLayoutWidgetSizing] minSpanX storedOverride '
          'provider=${widgetInfo.providerPackage}/${widgetInfo.providerClass} '
          'storedMinSpanX=${widgetInfo.minSpanX} gridColumns=${widget.settings.gridColumns} '
          'resizeMode=${widgetInfo.resizeMode} result=1',
        );
        return 1;
      }
      widgetLog(
        '[CellLayoutWidgetSizing] minSpanX stored '
        'provider=${widgetInfo.providerPackage}/${widgetInfo.providerClass} '
        'storedMinSpanX=${widgetInfo.minSpanX} gridColumns=${widget.settings.gridColumns} '
        'result=$span',
      );
      return span;
    }
    final sourceWidth = widgetInfo.minResizeWidth > 0
        ? widgetInfo.minResizeWidth
        : widgetInfo.minWidth;
    final span = _minSpanForSize(
      sourceWidth,
      _cellWidth,
      widget.settings.gridColumns,
    );
    if (span >= widget.settings.gridColumns &&
        _canResizeHorizontally(widgetInfo)) {
      widgetLog(
        '[CellLayoutWidgetSizing] minSpanX computedOverride '
        'provider=${widgetInfo.providerPackage}/${widgetInfo.providerClass} '
        'sourceWidth=$sourceWidth cellWidth=${_cellWidth.toStringAsFixed(2)} '
        'computed=$span gridColumns=${widget.settings.gridColumns} '
        'resizeMode=${widgetInfo.resizeMode} result=1',
      );
      return 1;
    }
    widgetLog(
      '[CellLayoutWidgetSizing] minSpanX computed '
      'provider=${widgetInfo.providerPackage}/${widgetInfo.providerClass} '
      'sourceWidth=$sourceWidth cellWidth=${_cellWidth.toStringAsFixed(2)} '
      'gridColumns=${widget.settings.gridColumns} result=$span',
    );
    return span;
  }

  int _minSpanYForWidget(LauncherWidgetInfo widgetInfo) {
    if (_isDefaultClockWidget(widgetInfo)) {
      return WorkspaceCubit.defaultClockMinSpanY
          .clamp(1, widget.settings.gridRows)
          .toInt();
    }
    if (widgetInfo.minSpanY > 0) {
      final span =
          widgetInfo.minSpanY.clamp(1, widget.settings.gridRows).toInt();
      if (span >= widget.settings.gridRows &&
          _canResizeVertically(widgetInfo)) {
        widgetLog(
          '[CellLayoutWidgetSizing] minSpanY storedOverride '
          'provider=${widgetInfo.providerPackage}/${widgetInfo.providerClass} '
          'storedMinSpanY=${widgetInfo.minSpanY} gridRows=${widget.settings.gridRows} '
          'resizeMode=${widgetInfo.resizeMode} result=1',
        );
        return 1;
      }
      widgetLog(
        '[CellLayoutWidgetSizing] minSpanY stored '
        'provider=${widgetInfo.providerPackage}/${widgetInfo.providerClass} '
        'storedMinSpanY=${widgetInfo.minSpanY} gridRows=${widget.settings.gridRows} '
        'result=$span',
      );
      return span;
    }
    final sourceHeight = widgetInfo.minResizeHeight > 0
        ? widgetInfo.minResizeHeight
        : widgetInfo.minHeight;
    final span = _minSpanForSize(
      sourceHeight,
      _cellHeight,
      widget.settings.gridRows,
    );
    if (span >= widget.settings.gridRows && _canResizeVertically(widgetInfo)) {
      widgetLog(
        '[CellLayoutWidgetSizing] minSpanY computedOverride '
        'provider=${widgetInfo.providerPackage}/${widgetInfo.providerClass} '
        'sourceHeight=$sourceHeight cellHeight=${_cellHeight.toStringAsFixed(2)} '
        'computed=$span gridRows=${widget.settings.gridRows} '
        'resizeMode=${widgetInfo.resizeMode} result=1',
      );
      return 1;
    }
    widgetLog(
      '[CellLayoutWidgetSizing] minSpanY computed '
      'provider=${widgetInfo.providerPackage}/${widgetInfo.providerClass} '
      'sourceHeight=$sourceHeight cellHeight=${_cellHeight.toStringAsFixed(2)} '
      'gridRows=${widget.settings.gridRows} result=$span',
    );
    return span;
  }

  int _maxSpanXForWidget(
    LauncherWidgetInfo widgetInfo, {
    required int minSpanX,
  }) {
    if (_isDefaultClockWidget(widgetInfo)) {
      return WorkspaceCubit.defaultClockMaxSpanX
          .clamp(minSpanX, widget.settings.gridColumns)
          .toInt();
    }
    if (widgetInfo.maxSpanX > 0) {
      return widgetInfo.maxSpanX
          .clamp(minSpanX, widget.settings.gridColumns)
          .toInt();
    }
    if (widgetInfo.maxResizeWidth <= 0) return widget.settings.gridColumns;
    return _maxSpanForSize(
      widgetInfo.maxResizeWidth,
      _cellWidth,
      widget.settings.gridColumns,
      minSpanX,
    );
  }

  // Stacks are capped one row below the grid height so a stack can never
  // fill the column. A full-height stack would block touching the page
  // background and would dominate the workspace visually.
  int _stackMaxRowSpan() => math.max(1, widget.settings.gridRows - 1);

  int _maxSpanYForWidget(
    LauncherWidgetInfo widgetInfo, {
    required int minSpanY,
  }) {
    if (_isDefaultClockWidget(widgetInfo)) {
      return WorkspaceCubit.defaultClockMaxSpanY
          .clamp(minSpanY, widget.settings.gridRows)
          .toInt();
    }
    if (widgetInfo.maxSpanY > 0) {
      return widgetInfo.maxSpanY
          .clamp(minSpanY, widget.settings.gridRows)
          .toInt();
    }
    if (widgetInfo.maxResizeHeight <= 0) return widget.settings.gridRows;
    return _maxSpanForSize(
      widgetInfo.maxResizeHeight,
      _cellHeight,
      widget.settings.gridRows,
      minSpanY,
    );
  }

  int _minSpanForSize(int size, double cellSize, int maxSpan) {
    if (size <= 0 || cellSize <= 0) return 1;
    final span = ((size + _gridGap) / (cellSize + _gridGap)).ceil();
    return span.clamp(1, maxSpan).toInt();
  }

  int _maxSpanForSize(
    int size,
    double cellSize,
    int maxSpan,
    int minSpan,
  ) {
    if (size <= 0 || cellSize <= 0) return maxSpan;
    final span = ((size + _gridGap) / (cellSize + _gridGap)).ceil();
    return span.clamp(minSpan, maxSpan).toInt();
  }

  bool _canResizeHorizontally(LauncherWidgetInfo widgetInfo) {
    if (_isDefaultClockWidget(widgetInfo)) return true;
    return (_effectiveResizeMode(widgetInfo) & _resizeHorizontal) != 0;
  }

  bool _canResizeVertically(LauncherWidgetInfo widgetInfo) {
    if (_isDefaultClockWidget(widgetInfo)) return true;
    return (_effectiveResizeMode(widgetInfo) & _resizeVertical) != 0;
  }

  int _effectiveResizeMode(LauncherWidgetInfo widgetInfo) {
    return widgetInfo.resizeMode;
  }

  bool _canResizeStackHorizontally(List<LauncherWidgetInfo> widgets) {
    return widgets.every(_canResizeHorizontally);
  }

  bool _canResizeStackVertically(List<LauncherWidgetInfo> widgets) {
    return widgets.every(_canResizeVertically);
  }

  bool _isDefaultClockWidget(LauncherWidgetInfo widgetInfo) {
    return widgetInfo.isCustomWidget &&
        widgetInfo.providerPackage ==
            WorkspaceCubit.defaultClockProviderPackage &&
        widgetInfo.providerClass == WorkspaceCubit.defaultClockProviderClass;
  }

  void _refreshWorkspaceWidgetMetadata() {
    if (_cellWidth <= 0 || _cellHeight <= 0) {
      widgetLog(
        '[CellLayoutWidgetSizing] refreshMetadata skipped invalidCell '
        'cell=${_cellWidth.toStringAsFixed(2)}x${_cellHeight.toStringAsFixed(2)}',
      );
      return;
    }
    if (context.read<AppsCubit>().drawerActive) {
      _lastRefreshedCellWidth = -1;
      _lastRefreshedCellHeight = -1;
      _lastWidgetMetadataRefreshKey = null;
      widgetLog(
        '[CellLayoutWidgetSizing] refreshMetadata skipped drawerActive '
        'page=${widget.pageIndex}',
      );
      return;
    }
    if (_workspacePageIsScrolling()) {
      _lastRefreshedCellWidth = -1;
      _lastRefreshedCellHeight = -1;
      _lastWidgetMetadataRefreshKey = null;
      widgetLog(
        '[CellLayoutWidgetSizing] refreshMetadata skipped pageScrolling '
        'page=${widget.pageIndex}',
      );
      return;
    }

    final placedWidgets = _placedSystemWidgetsForRefresh();
    if (placedWidgets.isEmpty) {
      widgetLog(
        '[CellLayoutWidgetSizing] refreshMetadata skipped noSystemWidgets '
        'page=${widget.pageIndex}',
      );
      return;
    }

    final widgetKey = placedWidgets
        .map((widget) =>
            '${widget.appWidgetId}:${widget.providerPackage}/${widget.providerClass}')
        .join(',');
    final key = [
      widget.settings.gridColumns,
      widget.settings.gridRows,
      _cellWidth.round(),
      _cellHeight.round(),
      _gridGap.round(),
      widgetKey,
    ].join(':');
    if (_lastWidgetMetadataRefreshKey == key) {
      widgetLog(
        '[CellLayoutWidgetSizing] refreshMetadata skipped sameKey key=$key',
      );
      return;
    }
    _lastWidgetMetadataRefreshKey = key;
    widgetLog(
      '[CellLayoutWidgetSizing] refreshMetadata request '
      'page=${widget.pageIndex} count=${placedWidgets.length} key=$key '
      'grid=${widget.settings.gridColumns}x${widget.settings.gridRows} '
      'cell=${_cellWidth.toStringAsFixed(2)}x${_cellHeight.toStringAsFixed(2)} gap=$_gridGap',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final stopwatch = Stopwatch()..start();
      final providers = await LauncherService.getPlacedWidgetProviderMetadata(
        widgets: placedWidgets,
        gridColumns: widget.settings.gridColumns,
        gridRows: widget.settings.gridRows,
        cellWidth: _cellWidth,
        cellHeight: _cellHeight,
        gap: _gridGap,
      );
      if (!mounted) return;
      widgetLog(
        '[CellLayoutWidgetSizing] refreshMetadata response '
        'page=${widget.pageIndex} requested=${placedWidgets.length} '
        'providers=${providers.length} durationMs=${stopwatch.elapsedMilliseconds}',
      );
      context.read<WorkspaceCubit>().refreshWidgetProviderMetadata(
            providers,
            widget.settings.gridColumns,
            widget.settings.gridRows,
          );
    });
  }

  bool _workspacePageIsScrolling() {
    final scrollable = Scrollable.maybeOf(context);
    return scrollable?.position.isScrollingNotifier.value ?? false;
  }

  List<LauncherWidgetInfo> _placedSystemWidgetsForRefresh() {
    final pages = context.read<WorkspaceCubit>().state.pages;
    final byKey = <String, LauncherWidgetInfo>{};
    for (final page in pages) {
      for (final content in page.slots.values) {
        if (content is WidgetSlot) {
          _collectRefreshWidget(content.widget, byKey);
        } else if (content is WidgetStackSlot) {
          for (final widgetInfo in content.widgets) {
            _collectRefreshWidget(widgetInfo, byKey);
          }
        }
      }
    }
    final widgets = byKey.values.toList(growable: false);
    widgets.sort((a, b) {
      final appWidgetCompare = a.appWidgetId.compareTo(b.appWidgetId);
      if (appWidgetCompare != 0) return appWidgetCompare;
      final packageCompare = a.providerPackage.compareTo(b.providerPackage);
      if (packageCompare != 0) return packageCompare;
      return a.providerClass.compareTo(b.providerClass);
    });
    return widgets;
  }

  void _collectRefreshWidget(
    LauncherWidgetInfo widgetInfo,
    Map<String, LauncherWidgetInfo> byKey,
  ) {
    if (widgetInfo.isCustomWidget) return;
    if (widgetInfo.appWidgetId <= 0) {
      widgetLog(
        '[CellLayoutWidgetSizing] refreshMetadata skipped invalidWidget '
        '${widgetInfo.providerPackage}/${widgetInfo.providerClass} id=${widgetInfo.appWidgetId}',
      );
      return;
    }
    byKey['${widgetInfo.appWidgetId}:${widgetInfo.providerPackage}/${widgetInfo.providerClass}'] =
        widgetInfo;
  }

  void _resizeSelectedWidgetBySteps(
    _WorkspaceResizeDirection direction,
    int dxSteps,
    int dySteps,
  ) {
    final slot = _selectedWidgetSlot;
    if (slot == null || (dxSteps == 0 && dySteps == 0)) return;
    final content = widget.page.slots[slot];

    switch (content) {
      case WidgetSlot(:final widget):
        if (!_canResizeHorizontally(widget)) dxSteps = 0;
        if (!_canResizeVertically(widget)) dySteps = 0;
        if (dxSteps == 0 && dySteps == 0) return;
        final minSpanX = _minSpanXForWidget(widget);
        final minSpanY = _minSpanYForWidget(widget);
        final (currentSpanX, currentSpanY) = _effectiveSpanForContent(content);
        final computedMaxSpanX = _maxSpanXForWidget(widget, minSpanX: minSpanX);
        final computedMaxSpanY = _maxSpanYForWidget(widget, minSpanY: minSpanY);
        widgetLog('[RESIZE] slot=$slot dir=$direction dx=$dxSteps dy=$dySteps '
            'minSpanX=$minSpanX maxSpanX=$computedMaxSpanX '
            'minSpanY=$minSpanY maxSpanY=$computedMaxSpanY '
            'currentSpanX=$currentSpanX currentSpanY=$currentSpanY '
            'storedMinSpanX=${widget.minSpanX} storedMaxSpanX=${widget.maxSpanX} '
            'storedMinSpanY=${widget.minSpanY} storedMaxSpanY=${widget.maxSpanY} '
            'resizeMode=${widget.resizeMode}');
        final candidate = _resizeCandidateFromSteps(
          direction: direction,
          currentSlot: slot,
          currentSpanX: currentSpanX,
          currentSpanY: currentSpanY,
          minSpanX: minSpanX,
          minSpanY: minSpanY,
          maxSpanX: computedMaxSpanX,
          maxSpanY: computedMaxSpanY,
          dxSteps: dxSteps,
          dySteps: dySteps,
        );
        widgetLog('[RESIZE] candidate=$candidate');
        if (candidate == null) return;
        final (nextSlot, nextSpanX, nextSpanY) = candidate;
        _resizeWidget(slot, widget, nextSlot, nextSpanX, nextSpanY);
      case WidgetStackSlot(:final widgets, :final spanX, :final spanY):
        if (!_canResizeStackHorizontally(widgets)) dxSteps = 0;
        if (!_canResizeStackVertically(widgets)) dySteps = 0;
        if (dxSteps == 0 && dySteps == 0) return;
        final minSpanX = widgets.fold<int>(
          1,
          (value, widget) => math.max(value, _minSpanXForWidget(widget)),
        );
        final minSpanY = widgets.fold<int>(
          1,
          (value, widget) => math.max(value, _minSpanYForWidget(widget)),
        );
        final maxSpanX = widgets.fold<int>(
          widget.settings.gridColumns,
          (value, widget) => math.min(
            value,
            _maxSpanXForWidget(
              widget,
              minSpanX: _minSpanXForWidget(widget),
            ),
          ),
        );
        final maxSpanY = widgets.fold<int>(
          _stackMaxRowSpan(),
          (value, widget) => math.min(
            value,
            _maxSpanYForWidget(
              widget,
              minSpanY: _minSpanYForWidget(widget),
            ),
          ),
        );
        final candidate = _resizeCandidateFromSteps(
          direction: direction,
          currentSlot: slot,
          currentSpanX:
              spanX.clamp(minSpanX, math.max(minSpanX, maxSpanX)).toInt(),
          currentSpanY:
              spanY.clamp(minSpanY, math.max(minSpanY, maxSpanY)).toInt(),
          minSpanX: minSpanX,
          minSpanY: minSpanY,
          maxSpanX: math.max(minSpanX, maxSpanX),
          maxSpanY: math.max(minSpanY, maxSpanY),
          dxSteps: dxSteps,
          dySteps: dySteps,
        );
        if (candidate == null) return;
        final (nextSlot, nextSpanX, nextSpanY) = candidate;
        _resizeWidgetStack(slot, content, nextSlot, nextSpanX, nextSpanY);
      default:
        break;
    }
  }

  (int slot, int spanX, int spanY)? _resizeCandidateFromSteps({
    required _WorkspaceResizeDirection direction,
    required int currentSlot,
    required int currentSpanX,
    required int currentSpanY,
    required int minSpanX,
    required int minSpanY,
    required int maxSpanX,
    required int maxSpanY,
    required int dxSteps,
    required int dySteps,
  }) {
    var nextSlot = currentSlot;
    var nextSpanX = currentSpanX;
    var nextSpanY = currentSpanY;

    if (direction.affectsLeft && dxSteps != 0) {
      final candidateSlot = nextSlot + dxSteps;
      final candidateSpanX = nextSpanX - dxSteps;
      final sameRow = candidateSlot >= 0 &&
          candidateSlot ~/ widget.settings.gridColumns ==
              nextSlot ~/ widget.settings.gridColumns;
      if (sameRow && candidateSpanX >= minSpanX && candidateSpanX <= maxSpanX) {
        nextSlot = candidateSlot;
        nextSpanX = candidateSpanX;
      }
    }

    if (direction.affectsRight && dxSteps != 0) {
      nextSpanX = (nextSpanX + dxSteps).clamp(minSpanX, maxSpanX);
    }

    if (direction.affectsTop && dySteps != 0) {
      final candidateSlot = nextSlot + dySteps * widget.settings.gridColumns;
      final candidateSpanY = nextSpanY - dySteps;
      if (candidateSlot >= 0 &&
          candidateSpanY >= minSpanY &&
          candidateSpanY <= maxSpanY) {
        nextSlot = candidateSlot;
        nextSpanY = candidateSpanY;
      }
    }

    if (direction.affectsBottom && dySteps != 0) {
      nextSpanY = (nextSpanY + dySteps).clamp(minSpanY, maxSpanY);
    }

    if (nextSlot == currentSlot &&
        nextSpanX == currentSpanX &&
        nextSpanY == currentSpanY) {
      return null;
    }
    return (nextSlot, nextSpanX, nextSpanY);
  }

  void _resizeWidget(
    int currentSlot,
    LauncherWidgetInfo widgetInfo,
    int nextSlot,
    int nextSpanX,
    int nextSpanY,
  ) {
    final minSpanX = _minSpanXForWidget(widgetInfo);
    final minSpanY = _minSpanYForWidget(widgetInfo);
    final maxSpanX = _maxSpanXForWidget(widgetInfo, minSpanX: minSpanX);
    final maxSpanY = _maxSpanYForWidget(widgetInfo, minSpanY: minSpanY);
    final (currentSpanX, currentSpanY) =
        _effectiveSpanForContent(WidgetSlot(widgetInfo));
    final requestedSpanX = nextSpanX.clamp(minSpanX, maxSpanX).toInt();
    final requestedSpanY = nextSpanY.clamp(minSpanY, maxSpanY).toInt();
    final resolved = _resolveResizeCandidate(
      currentSlot: currentSlot,
      currentSpanX: currentSpanX,
      currentSpanY: currentSpanY,
      requestedSlot: nextSlot,
      requestedSpanX: requestedSpanX,
      requestedSpanY: requestedSpanY,
    );
    if (resolved == null) {
      return;
    }
    final (resolvedSlot, resolvedSpanX, resolvedSpanY) = resolved;

    final workspace = context.read<WorkspaceCubit>();
    final updated =
        widgetInfo.copyWith(spanX: resolvedSpanX, spanY: resolvedSpanY);
    if (currentSlot == resolvedSlot) {
      workspace.updateWidgetSpan(widget.pageIndex, currentSlot, updated);
      return;
    }

    workspace.moveItem(
        widget.pageIndex, currentSlot, widget.pageIndex, resolvedSlot);
    workspace.updateWidgetSpan(widget.pageIndex, resolvedSlot, updated);
    if (mounted) {
      setState(() => _selectedWidgetSlot = resolvedSlot);
      _syncSelectionGuard();
    }
  }

  void _resizeWidgetStack(
    int currentSlot,
    WidgetStackSlot stack,
    int nextSlot,
    int nextSpanX,
    int nextSpanY,
  ) {
    final (currentSpanX, currentSpanY) =
        _effectiveSpanForContent(WidgetStackSlot(
      stack.widgets,
      spanX: stack.spanX,
      spanY: stack.spanY,
      currentIndex: stack.currentIndex,
    ));
    final minSpanX = stack.widgets.fold<int>(
      1,
      (value, widget) => math.max(value, _minSpanXForWidget(widget)),
    );
    final minSpanY = stack.widgets.fold<int>(
      1,
      (value, widget) => math.max(value, _minSpanYForWidget(widget)),
    );
    final maxSpanX = stack.widgets.fold<int>(
      widget.settings.gridColumns,
      (value, widget) => math.min(
        value,
        _maxSpanXForWidget(
          widget,
          minSpanX: _minSpanXForWidget(widget),
        ),
      ),
    );
    final maxSpanY = stack.widgets.fold<int>(
      _stackMaxRowSpan(),
      (value, widget) => math.min(
        value,
        _maxSpanYForWidget(
          widget,
          minSpanY: _minSpanYForWidget(widget),
        ),
      ),
    );
    final resolved = _resolveResizeCandidate(
      currentSlot: currentSlot,
      currentSpanX: currentSpanX,
      currentSpanY: currentSpanY,
      requestedSlot: nextSlot,
      requestedSpanX:
          nextSpanX.clamp(minSpanX, math.max(minSpanX, maxSpanX)).toInt(),
      requestedSpanY:
          nextSpanY.clamp(minSpanY, math.max(minSpanY, maxSpanY)).toInt(),
    );
    if (resolved == null) {
      return;
    }
    final (resolvedSlot, resolvedSpanX, resolvedSpanY) = resolved;

    final workspace = context.read<WorkspaceCubit>();
    if (currentSlot != resolvedSlot) {
      workspace.moveItem(
          widget.pageIndex, currentSlot, widget.pageIndex, resolvedSlot);
    }
    workspace.updateWidgetStackSpan(
      widget.pageIndex,
      resolvedSlot,
      resolvedSpanX,
      resolvedSpanY,
    );
    if (mounted) {
      setState(() => _selectedWidgetSlot = resolvedSlot);
      _syncSelectionGuard();
    }
  }

  (int slot, int spanX, int spanY)? _resolveResizeCandidate({
    required int currentSlot,
    required int currentSpanX,
    required int currentSpanY,
    required int requestedSlot,
    required int requestedSpanX,
    required int requestedSpanY,
  }) {
    final slotDelta = requestedSlot - currentSlot;
    final spanXDelta = requestedSpanX - currentSpanX;
    final spanYDelta = requestedSpanY - currentSpanY;
    final maxSteps = [
      slotDelta.abs(),
      spanXDelta.abs(),
      spanYDelta.abs(),
      1,
    ].reduce(math.max);

    for (int step = maxSteps; step >= 0; step--) {
      final progress = step / maxSteps;
      final candidateSlot = currentSlot + (slotDelta * progress).round();
      final candidateSpanX = currentSpanX + (spanXDelta * progress).round();
      final candidateSpanY = currentSpanY + (spanYDelta * progress).round();

      if (_canPlaceWidgetAt(
        widget.page,
        candidateSlot,
        candidateSpanX,
        candidateSpanY,
        widget.settings.gridColumns,
        widget.settings.gridRows,
        ignoreAnchorSlot: currentSlot,
      )) {
        return (candidateSlot, candidateSpanX, candidateSpanY);
      }
    }

    return null;
  }
}

enum _WorkspaceResizeDirection {
  left,
  top,
  right,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight;

  bool get affectsLeft => this == left || this == topLeft || this == bottomLeft;
  bool get affectsTop => this == top || this == topLeft || this == topRight;
  bool get affectsRight =>
      this == right || this == topRight || this == bottomRight;
  bool get affectsBottom =>
      this == bottom || this == bottomLeft || this == bottomRight;
}

class _WorkspaceWidgetResizeFrame extends StatefulWidget {
  static const double _edgeHitSize = 34;
  static const double _cornerHitSize = 54;
  static const double touchOutset = _cornerHitSize / 2;

  final double contentOutset;
  final double stepX;
  final double stepY;
  final bool showDebugHitZones;
  final VoidCallback onDismiss;
  final void Function(
    _WorkspaceResizeDirection direction,
    int dxSteps,
    int dySteps,
  ) onResizeSteps;

  const _WorkspaceWidgetResizeFrame({
    required this.contentOutset,
    required this.stepX,
    required this.stepY,
    required this.showDebugHitZones,
    required this.onDismiss,
    required this.onResizeSteps,
  });

  @override
  State<_WorkspaceWidgetResizeFrame> createState() =>
      _WorkspaceWidgetResizeFrameState();
}

class _WorkspaceWidgetResizeFrameState
    extends State<_WorkspaceWidgetResizeFrame> {
  _WorkspaceResizeDirection? _previewDirection;
  double _previewDx = 0;
  double _previewDy = 0;

  @override
  Widget build(BuildContext context) {
    final preview = _previewInsets();
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentRect = Rect.fromLTWH(
          widget.contentOutset,
          widget.contentOutset,
          math.max(0, constraints.maxWidth - widget.contentOutset * 2),
          math.max(0, constraints.maxHeight - widget.contentOutset * 2),
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(
              rect: contentRect,
              // While a widget is selected, the body must swallow swipes so
              // the workspace PageView can't page through them — any swipe
              // dismisses the selection instead. A plain GestureDetector with
              // onHorizontalDragStart loses the arena to PageView because
              // both have the same ~18px slop and PageView claims first on
              // the parent edge of the arena. The eager pan recognizer below
              // accepts at 8px, beating PageView to victory.
              //
              // Long-press is deliberately not registered here so it falls
              // through to the sibling LongPressDraggable wrapping the
              // widget below (re-arming a move drag). Translucent (not
              // opaque) preserves that fall-through path.
              child: RawGestureDetector(
                behavior: HitTestBehavior.translucent,
                gestures: <Type, GestureRecognizerFactory>{
                  TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                      TapGestureRecognizer>(
                    () => TapGestureRecognizer(),
                    (r) => r.onTap = widget.onDismiss,
                  ),
                  _EagerDismissPanGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          _EagerDismissPanGestureRecognizer>(
                    () => _EagerDismissPanGestureRecognizer(),
                    (r) => r.onStart = (_) => widget.onDismiss(),
                  ),
                },
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: contentRect.left + preview.left,
              top: contentRect.top + preview.top,
              width: math.max(
                0,
                contentRect.width - preview.left - preview.right,
              ),
              height: math.max(
                0,
                contentRect.height - preview.top - preview.bottom,
              ),
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: _previewDirection == null
                      ? const Duration(milliseconds: 120)
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.55),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
            ),
            _edge(_WorkspaceResizeDirection.left, contentRect),
            _edge(_WorkspaceResizeDirection.top, contentRect),
            _edge(_WorkspaceResizeDirection.right, contentRect),
            _edge(_WorkspaceResizeDirection.bottom, contentRect),
            _corner(_WorkspaceResizeDirection.topLeft, contentRect),
            _corner(_WorkspaceResizeDirection.topRight, contentRect),
            _corner(_WorkspaceResizeDirection.bottomLeft, contentRect),
            _corner(_WorkspaceResizeDirection.bottomRight, contentRect),
          ],
        );
      },
    );
  }

  Widget _edge(_WorkspaceResizeDirection direction, Rect contentRect) {
    final isVertical = direction == _WorkspaceResizeDirection.left ||
        direction == _WorkspaceResizeDirection.right;
    final child = _WorkspaceResizeDragTarget(
      direction: direction,
      stepX: widget.stepX,
      stepY: widget.stepY,
      showDebugHitZone: widget.showDebugHitZones,
      onPreviewChanged: _setPreview,
      onPreviewEnded: _clearPreview,
      onResizeSteps: widget.onResizeSteps,
      child: const SizedBox.expand(),
    );

    final left = switch (direction) {
      _WorkspaceResizeDirection.left =>
        contentRect.left - _WorkspaceWidgetResizeFrame._edgeHitSize / 2,
      _WorkspaceResizeDirection.right =>
        contentRect.right - _WorkspaceWidgetResizeFrame._edgeHitSize / 2,
      _ => contentRect.left,
    };
    final top = switch (direction) {
      _WorkspaceResizeDirection.top =>
        contentRect.top - _WorkspaceWidgetResizeFrame._edgeHitSize / 2,
      _WorkspaceResizeDirection.bottom =>
        contentRect.bottom - _WorkspaceWidgetResizeFrame._edgeHitSize / 2,
      _ => contentRect.top,
    };

    return Positioned(
      left: left,
      top: top,
      width: isVertical
          ? _WorkspaceWidgetResizeFrame._edgeHitSize
          : contentRect.width,
      height: isVertical
          ? contentRect.height
          : _WorkspaceWidgetResizeFrame._edgeHitSize,
      child: child,
    );
  }

  Widget _corner(_WorkspaceResizeDirection direction, Rect contentRect) {
    final hitSize = _WorkspaceWidgetResizeFrame._cornerHitSize;
    return Positioned(
      left: direction.affectsLeft
          ? contentRect.left - hitSize / 2
          : contentRect.right - hitSize / 2,
      top: direction.affectsTop
          ? contentRect.top - hitSize / 2
          : contentRect.bottom - hitSize / 2,
      width: hitSize,
      height: hitSize,
      child: _WorkspaceResizeDragTarget(
        direction: direction,
        stepX: widget.stepX,
        stepY: widget.stepY,
        showDebugHitZone: widget.showDebugHitZones,
        onPreviewChanged: _setPreview,
        onPreviewEnded: _clearPreview,
        onResizeSteps: widget.onResizeSteps,
        child: CustomPaint(
          painter: _CornerBracketPainter(direction: direction),
          size: Size.square(_WorkspaceWidgetResizeFrame._cornerHitSize),
        ),
      ),
    );
  }

  EdgeInsets _previewInsets() {
    final direction = _previewDirection;
    if (direction == null) return EdgeInsets.zero;
    return EdgeInsets.only(
      left: direction.affectsLeft ? _previewDx : 0,
      right: direction.affectsRight ? -_previewDx : 0,
      top: direction.affectsTop ? _previewDy : 0,
      bottom: direction.affectsBottom ? -_previewDy : 0,
    );
  }

  void _setPreview(
    _WorkspaceResizeDirection direction,
    double dx,
    double dy,
  ) {
    final nextDx =
        (direction.affectsLeft || direction.affectsRight ? dx : 0).toDouble();
    final nextDy =
        (direction.affectsTop || direction.affectsBottom ? dy : 0).toDouble();
    if (_previewDirection == direction &&
        _previewDx == nextDx &&
        _previewDy == nextDy) {
      return;
    }
    setState(() {
      _previewDirection = direction;
      _previewDx = nextDx;
      _previewDy = nextDy;
    });
  }

  void _clearPreview() {
    if (_previewDirection == null && _previewDx == 0 && _previewDy == 0) {
      return;
    }
    setState(() {
      _previewDirection = null;
      _previewDx = 0;
      _previewDy = 0;
    });
  }
}

class _WorkspaceResizeDragTarget extends StatefulWidget {
  final _WorkspaceResizeDirection direction;
  final double stepX;
  final double stepY;
  final bool showDebugHitZone;
  final void Function(
    _WorkspaceResizeDirection direction,
    int dxSteps,
    int dySteps,
  ) onResizeSteps;
  final void Function(
    _WorkspaceResizeDirection direction,
    double dx,
    double dy,
  ) onPreviewChanged;
  final VoidCallback onPreviewEnded;
  final Widget child;

  const _WorkspaceResizeDragTarget({
    required this.direction,
    required this.stepX,
    required this.stepY,
    required this.showDebugHitZone,
    required this.onResizeSteps,
    required this.onPreviewChanged,
    required this.onPreviewEnded,
    required this.child,
  });

  @override
  State<_WorkspaceResizeDragTarget> createState() =>
      _WorkspaceResizeDragTargetState();
}

class _WorkspaceResizeDragTargetState
    extends State<_WorkspaceResizeDragTarget> {
  double _dx = 0;
  double _dy = 0;
  int? _activePointer;

  @override
  void dispose() {
    if (_activePointer != null) {
      WidgetResizeGestureGuard.end();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stepX = widget.stepX.clamp(24, double.infinity).toDouble();
    final stepY = widget.stepY.clamp(24, double.infinity).toDouble();

    return RawGestureDetector(
      gestures: {
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
          () => EagerGestureRecognizer(),
          (_) {},
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (_activePointer != null) return;
          _activePointer = event.pointer;
          _dx = 0;
          _dy = 0;
          WidgetResizeGestureGuard.begin();
          widget.onPreviewChanged(widget.direction, 0, 0);
        },
        onPointerMove: (event) {
          if (_activePointer != event.pointer) return;
          _dx += event.delta.dx;
          _dy += event.delta.dy;
          _commitWholeSteps(stepX, stepY);
          widget.onPreviewChanged(widget.direction, _dx, _dy);
        },
        onPointerUp: (event) {
          if (_activePointer != event.pointer) return;
          _finishResize(stepX, stepY);
        },
        onPointerCancel: (event) {
          if (_activePointer != event.pointer) return;
          _finishResize(stepX, stepY);
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.showDebugHitZone
                ? Colors.yellow.withValues(alpha: 0.28)
                : Colors.transparent,
            border: widget.showDebugHitZone
                ? Border.all(
                    color: Colors.yellowAccent.withValues(alpha: 0.9),
                    width: 1.4,
                  )
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }

  void _finishResize(double stepX, double stepY) {
    _commitSnapSteps(stepX, stepY);
    widget.onPreviewEnded();
    WidgetResizeGestureGuard.end();
    _activePointer = null;
  }

  void _commitWholeSteps(double stepX, double stepY) {
    final dxSteps = _wholeStepsForDelta(_dx, stepX);
    final dySteps = _wholeStepsForDelta(_dy, stepY);
    if (dxSteps != 0 || dySteps != 0) {
      widget.onResizeSteps(widget.direction, dxSteps, dySteps);
      _dx -= dxSteps * stepX;
      _dy -= dySteps * stepY;
    }
  }

  void _commitSnapSteps(double stepX, double stepY) {
    final dxSteps = _snapStepsForDelta(_dx, stepX);
    final dySteps = _snapStepsForDelta(_dy, stepY);
    if (dxSteps != 0 || dySteps != 0) {
      widget.onResizeSteps(widget.direction, dxSteps, dySteps);
    }
    _dx = 0;
    _dy = 0;
  }

  int _wholeStepsForDelta(double delta, double step) {
    if (step <= 0) return 0;
    return (delta / step).truncate();
  }

  int _snapStepsForDelta(double delta, double step) {
    if (step <= 0) return 0;
    if (delta.abs() < step * 0.16) return 0;
    return (delta / step).round();
  }
}

class _WidgetActionMenu extends StatelessWidget {
  final bool isStack;
  final VoidCallback onInfo;
  final VoidCallback onCreateOrEditStack;
  final VoidCallback onRemove;

  const _WidgetActionMenu({
    required this.isStack,
    required this.onInfo,
    required this.onCreateOrEditStack,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xE61F1F22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: _WidgetActionTile(
                icon: Icons.info_outline,
                label: 'Info',
                onTap: onInfo,
              ),
            ),
            Expanded(
              child: _WidgetActionTile(
                icon: isStack
                    ? Icons.dashboard_customize_outlined
                    : Icons.add_box_outlined,
                label: isStack ? 'Edit stack' : 'Create stack',
                onTap: onCreateOrEditStack,
              ),
            ),
            Expanded(
              child: _WidgetActionTile(
                icon: Icons.delete_outline,
                label: 'Remove',
                onTap: onRemove,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WidgetActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _WidgetActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  final _WorkspaceResizeDirection direction;

  const _CornerBracketPainter({required this.direction});

  @override
  void paint(Canvas canvas, Size size) {
    // Bracket arms curve into each other through a rounded corner so the
    // dragged corner follows the widget's own border radius instead of
    // pointing inward with a sharp 90° elbow.
    const armLength = 22.0;
    const outset = 6.0;
    const stroke = 3.0;
    const cornerRadius = 12.0;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final hx = direction.affectsLeft ? cx - outset : cx + outset;
    final hy = direction.affectsTop ? cy - outset : cy + outset;
    // Arm tip is past the curve.
    final horizSignX = direction.affectsLeft ? 1.0 : -1.0;
    final vertSignY = direction.affectsTop ? 1.0 : -1.0;
    final horizTipX = hx + horizSignX * armLength;
    final vertTipY = hy + vertSignY * armLength;
    // Points where the straight arms meet the rounded corner.
    final horizArmStartX = hx + horizSignX * cornerRadius;
    final vertArmStartY = hy + vertSignY * cornerRadius;

    final path = Path()
      ..moveTo(horizTipX, hy)
      ..lineTo(horizArmStartX, hy)
      ..quadraticBezierTo(hx, hy, hx, vertArmStartY)
      ..lineTo(hx, vertTipY);

    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.black.withValues(alpha: 0.45)
      ..strokeWidth = stroke + 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawPath(path, shadow);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerBracketPainter old) => old.direction != direction;
}

enum _StackEditAction { addWidget }

const double _stackEditViewportFraction = 0.86;
const double _stackEditMaxPreviewScale = 0.88;
const double _stackEditMinPreviewScale = 0.42;
const double _stackEditBadgeOverhang = 14.0;
const double _stackEditPanelHeightFraction = 0.75;
const double _stackEditPanelVerticalAlignment = 0.25;
const double _stackEditPanelHorizontalMargin = 20.0;
const double _stackEditPanelHorizontalPadding = 16.0;
const double _stackEditPanelVerticalPadding = 28.0;

/// Full-screen dimmed overlay that shows every widget in a stack as a live
/// tile in a horizontal scrollable row, each with an iOS-style red minus
/// badge for removal, and a trailing "+" tile for adding another widget.
class _StackEditOverlay extends StatefulWidget {
  final WidgetStackSlot stack;
  final double cellWidth;
  final double cellHeight;
  final double gap;
  final int gridColumns;
  final int gridRows;
  final bool canAddWidget;
  final void Function(int index) onRemoveAt;
  final VoidCallback onAddWidget;
  final VoidCallback onDismiss;

  const _StackEditOverlay({
    required this.stack,
    required this.cellWidth,
    required this.cellHeight,
    required this.gap,
    required this.gridColumns,
    required this.gridRows,
    required this.canAddWidget,
    required this.onRemoveAt,
    required this.onAddWidget,
    required this.onDismiss,
  });

  @override
  State<_StackEditOverlay> createState() => _StackEditOverlayState();
}

class _StackEditOverlayState extends State<_StackEditOverlay> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // viewportFraction < 1 makes adjacent pages peek from the sides.
    _controller = PageController(viewportFraction: _stackEditViewportFraction);
  }

  @override
  void didUpdateWidget(_StackEditOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pageCount =
        widget.stack.widgets.length + (widget.canAddWidget ? 1 : 0);
    final nextIndex =
        pageCount == 0 ? 0 : _index.clamp(0, pageCount - 1).toInt();
    if (nextIndex == _index) return;
    _index = nextIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpToPage(nextIndex);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pageCount =
        widget.stack.widgets.length + (widget.canAddWidget ? 1 : 0);
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final panelWidth = math.max(
              0.0,
              constraints.maxWidth - _stackEditPanelHorizontalMargin * 2,
            );
            final panelHeight =
                constraints.maxHeight * _stackEditPanelHeightFraction;
            final viewportWidth = math.max(
              0.0,
              panelWidth - _stackEditPanelHorizontalPadding * 2,
            );
            final itemWidth = viewportWidth * _stackEditViewportFraction;
            final dotsHeight = pageCount > 1 ? 31.0 : 0.0;
            final maxTileWidth =
                math.max(0.0, itemWidth - _stackEditBadgeOverhang - 8);
            final maxTileHeight = math.max(
              0.0,
              panelHeight -
                  _stackEditPanelVerticalPadding * 2 -
                  _stackEditBadgeOverhang * 2 -
                  dotsHeight -
                  32,
            );
            final fullTileWidth = widget.cellWidth * widget.stack.spanX +
                widget.gap * (widget.stack.spanX - 1);
            final fullTileHeight = widget.cellHeight * widget.stack.spanY +
                widget.gap * (widget.stack.spanY - 1);
            final previewScale = _stackEditPreviewScale(
              fullTileWidth: fullTileWidth,
              fullTileHeight: fullTileHeight,
              maxTileWidth: maxTileWidth,
              maxTileHeight: maxTileHeight,
            );
            final scaledCellWidth = widget.cellWidth * previewScale;
            final scaledCellHeight = widget.cellHeight * previewScale;
            final scaledGap = widget.gap * previewScale;
            final tileWidth = scaledCellWidth * widget.stack.spanX +
                scaledGap * (widget.stack.spanX - 1);
            final tileHeight = scaledCellHeight * widget.stack.spanY +
                scaledGap * (widget.stack.spanY - 1);

            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onDismiss,
                  ),
                ),
                Align(
                  alignment:
                      const Alignment(0, _stackEditPanelVerticalAlignment),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _stackEditPanelHorizontalMargin,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: panelWidth,
                        minHeight: panelHeight,
                        maxHeight: panelHeight,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(36),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                          child: Container(
                            key: const ValueKey('stack-edit-panel'),
                            decoration: BoxDecoration(
                              // Translucent white frosted panel — the blurred
                              // wallpaper bleeds through.
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(36),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                                width: 1,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: _stackEditPanelHorizontalPadding,
                              vertical: _stackEditPanelVerticalPadding,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                SizedBox(
                                  width: viewportWidth,
                                  height:
                                      tileHeight + _stackEditBadgeOverhang * 2,
                                  child: PageView.builder(
                                    controller: _controller,
                                    itemCount: pageCount,
                                    onPageChanged: (i) =>
                                        setState(() => _index = i),
                                    itemBuilder: (_, i) {
                                      final isAdd =
                                          i >= widget.stack.widgets.length;
                                      return Center(
                                        child: isAdd
                                            ? _StackEditAddTile(
                                                width: tileWidth,
                                                height: tileHeight,
                                                onTap: widget.onAddWidget,
                                              )
                                            : _StackEditTile(
                                                key: ValueKey(
                                                  'stack-edit-widget-${widget.stack.widgets[i].appWidgetId}',
                                                ),
                                                widgetInfo:
                                                    widget.stack.widgets[i],
                                                stackSpanX: widget.stack.spanX,
                                                stackSpanY: widget.stack.spanY,
                                                gridColumns: widget.gridColumns,
                                                gridRows: widget.gridRows,
                                                cellWidth: scaledCellWidth,
                                                cellHeight: scaledCellHeight,
                                                gap: scaledGap,
                                                tileWidth: tileWidth,
                                                tileHeight: tileHeight,
                                                onRemove: () =>
                                                    widget.onRemoveAt(i),
                                              ),
                                      );
                                    },
                                  ),
                                ),
                                if (pageCount > 1) ...[
                                  const SizedBox(height: 22),
                                  _OverlayPageDots(
                                    count: pageCount,
                                    current: _index,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

double _stackEditPreviewScale({
  required double fullTileWidth,
  required double fullTileHeight,
  required double maxTileWidth,
  required double maxTileHeight,
}) {
  if (fullTileWidth <= 0 || fullTileHeight <= 0) {
    return _stackEditMaxPreviewScale;
  }
  final widthScale = maxTileWidth / fullTileWidth;
  final heightScale = maxTileHeight / fullTileHeight;
  final fitScale = math.min(
    _stackEditMaxPreviewScale,
    math.min(widthScale, heightScale),
  );
  if (!fitScale.isFinite || fitScale <= 0) {
    return _stackEditMinPreviewScale;
  }
  return fitScale
      .clamp(_stackEditMinPreviewScale, _stackEditMaxPreviewScale)
      .toDouble();
}

class _StackEditTile extends StatelessWidget {
  final LauncherWidgetInfo widgetInfo;
  final int stackSpanX;
  final int stackSpanY;
  final int gridColumns;
  final int gridRows;
  final double cellWidth;
  final double cellHeight;
  final double gap;
  final double tileWidth;
  final double tileHeight;
  final VoidCallback onRemove;

  const _StackEditTile({
    super.key,
    required this.widgetInfo,
    required this.stackSpanX,
    required this.stackSpanY,
    required this.gridColumns,
    required this.gridRows,
    required this.cellWidth,
    required this.cellHeight,
    required this.gap,
    required this.tileWidth,
    required this.tileHeight,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('stack-edit-tile-frame'),
      width: tileWidth + _stackEditBadgeOverhang,
      height: tileHeight + _stackEditBadgeOverhang,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 7,
            top: 7,
            width: tileWidth,
            height: tileHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: StackWidgetTile(
                  widgetInfo: widgetInfo,
                  stackSpanX: stackSpanX,
                  stackSpanY: stackSpanY,
                  gridColumns: gridColumns,
                  gridRows: gridRows,
                  cellWidth: cellWidth,
                  cellHeight: cellHeight,
                  gap: gap,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: _RemoveBadge(onTap: onRemove),
          ),
        ],
      ),
    );
  }
}

class _StackEditAddTile extends StatelessWidget {
  final double width;
  final double height;
  final VoidCallback onTap;

  const _StackEditAddTile({
    required this.width,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.add,
              color: Colors.white,
              size: 36,
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoveBadge extends StatelessWidget {
  final VoidCallback onTap;

  const _RemoveBadge({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Color(0xFFE5484D),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Container(
              width: 12,
              height: 2,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayPageDots extends StatelessWidget {
  final int count;
  final int current;

  const _OverlayPageDots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 9 : 7,
          height: active ? 9 : 7,
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.95)
                : Colors.white.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}

// Pan recognizer with reduced slop so it accepts the gesture arena before
// the workspace PageView's horizontal drag recognizer (which uses the
// default ~18px slop). Used by the selected-widget resize frame to ensure
// a swipe on the widget body dismisses the selection instead of paging.
class _EagerDismissPanGestureRecognizer extends PanGestureRecognizer {
  @override
  bool hasSufficientGlobalDistanceToAccept(
      PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) {
    return globalDistanceMoved.abs() > 8.0;
  }
}

class _WidgetEdgeLongPressGestureRecognizer extends LongPressGestureRecognizer {
  _WidgetEdgeLongPressGestureRecognizer()
      : super(duration: const Duration(milliseconds: 350));
}
