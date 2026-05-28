import 'package:flutter/foundation.dart';


/// Global lock that says "the home screen is currently in some kind of
/// edit/resize mode and any swipe/tap action that would otherwise navigate
/// (open drawer, change page, open search, etc.) should be intercepted and
/// turned into a dismiss instead."
///
/// There are three independent things that need to set this lock, and they
/// MUST all use the same source of truth so the swipe-up handler can't drift
/// from the page-scroll lock in cell_layout's eager pan recognizer:
///
///   1. Per-widget resize selection (`_selectedWidgetSlot` in
///      `_CellLayoutViewState`). Set imperatively via [setSelectionActive].
///   2. Per-pointer touch on a resize handle. Set via [begin]/[end]
///      reference-counted by the resize drag target.
///   3. Global home-screen edit-mode overlay (`_editMode` in
///      `_HomeScreenState`, the One UI–style wallpaper/widgets/settings
///      picker). Set imperatively via [setOverlayActive].
///
/// [isResizing] returns true if ANY of the three is active.
class WidgetResizeGestureGuard {
  WidgetResizeGestureGuard._();

  // (1) Selection — imperative, owned by cell_layout.
  static bool _selectionActive = false;
  // (2) Resize-handle pointer count — reference-counted by the drag target.
  static int _activePointers = 0;
  // (3) Global edit-mode overlay — imperative, owned by home_screen.
  static bool _overlayActive = false;

  static final ValueNotifier<bool> isResizingNotifier =
      ValueNotifier<bool>(false);

  /// Fires specifically when handle-pointer activity flips on/off. We can't
  /// piggy-back on [isResizingNotifier] for this because [_selectionActive]
  /// is usually already true when the user presses a handle, so [isResizing]
  /// doesn't change value and the ValueNotifier short-circuits without
  /// notifying listeners — and the action menu would never hide.
  static final ValueNotifier<bool> isHandlePointerActiveNotifier =
      ValueNotifier<bool>(false);

  static bool get isResizing =>
      _selectionActive || _activePointers > 0 || _overlayActive;

  /// True iff a pointer is currently down on a resize handle. The workspace
  /// swipe-listener uses this to suppress its "any swipe while edit mode is
  /// active dismisses edit mode" rule WHILE the user is actively dragging a
  /// handle — otherwise the resize gesture itself crosses the swipe threshold
  /// and dismisses edit mode before the resize lands.
  static bool get isHandlePointerActive => _activePointers > 0;

  /// Optional dismiss hook. The currently-selected CellLayoutView wires
  /// this to its _clearWidgetResizeSelection so that any gesture path
  /// OUTSIDE the cell layout (e.g. the dock's own GestureDetector) can
  /// ask edit mode to exit. Without this, swipes that start over the
  /// dock never reach the cell-layout dismiss catcher and edit mode
  /// appears to "ignore" them.
  static VoidCallback? onRequestDismiss;

  static void requestDismiss() {
    final cb = onRequestDismiss;
    if (cb != null) cb();
  }

  static void _publish() {
    isResizingNotifier.value = isResizing;
    isHandlePointerActiveNotifier.value = _activePointers > 0;
  }

  // ── (1) Selection ──────────────────────────────────────────────────────────
  static void setSelectionActive(bool active) {
    if (_selectionActive == active) return;
    _selectionActive = active;
    _publish();
  }

  // ── (2) Resize-handle pointers ─────────────────────────────────────────────
  static void begin() {
    _activePointers += 1;
    _publish();
  }

  static void end() {
    if (_activePointers == 0) return;
    _activePointers -= 1;
    _publish();
  }

  // ── (3) Global edit-mode overlay ───────────────────────────────────────────
  static void setOverlayActive(bool active) {
    if (_overlayActive == active) return;
    _overlayActive = active;
    _publish();
  }

  static void reset() {
    _activePointers = 0;
    _selectionActive = false;
    _overlayActive = false;
    _publish();
  }
}
