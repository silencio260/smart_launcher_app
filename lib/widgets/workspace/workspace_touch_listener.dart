import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../models/launcher_settings.dart';
import '../../services/drag/drag_controller.dart';
import '../../services/gestures/widget_resize_gesture_guard.dart';

class WorkspaceTouchListener extends StatefulWidget {
  final Widget child;
  final LauncherSettings settings;
  final DragController dragController;
  final VoidCallback onSwipeUp;
  final VoidCallback onSwipeDown;
  final VoidCallback onDoubleTap;
  final VoidCallback onLongPress;

  const WorkspaceTouchListener({
    super.key,
    required this.child,
    required this.settings,
    required this.dragController,
    required this.onSwipeUp,
    required this.onSwipeDown,
    required this.onDoubleTap,
    required this.onLongPress,
  });

  @override
  State<WorkspaceTouchListener> createState() => _WorkspaceTouchListenerState();
}

class _WorkspaceTouchListenerState extends State<WorkspaceTouchListener>
    with SingleTickerProviderStateMixin {
  // Damped vertical offset so a failed micro-swipe pulls the workspace
  // slightly before snapping back, giving visible feedback even when the
  // velocity threshold isn't crossed.
  final ValueNotifier<double> _verticalOffset = ValueNotifier<double>(0);
  late final AnimationController _spring;
  double _springFrom = 0;
  bool _longPressFired = false;

  // Pointer-level tracking that bypasses the gesture arena. Curving/slanted
  // swipes often lose the vertical recognizer to PageView's horizontal one
  // or to an AndroidView's recognizers mid-gesture, so _onVerticalDragEnd
  // never fires. Listener sees every PointerMove regardless of arena state,
  // so we can decide based on raw net displacement from the touch-down.
  final Map<int, _PointerTrack> _tracks = {};
  static const double _fireThreshold = 56.0;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        _verticalOffset.value =
            _springFrom * (1 - Curves.easeOutCubic.transform(_spring.value));
      });
  }

  @override
  void dispose() {
    _spring.dispose();
    _verticalOffset.dispose();
    super.dispose();
  }

  bool get _blocked =>
      WidgetResizeGestureGuard.isResizing || widget.dragController.isDragging;

  void _onLongPressStart(LongPressStartDetails _) {
    if (_blocked) return;
    _longPressFired = true;
    widget.onLongPress();
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (_blocked || _longPressFired) return;
    if (_spring.isAnimating) _spring.stop();
    final next = (_verticalOffset.value + (d.primaryDelta ?? 0) * 0.35)
        .clamp(-72.0, 72.0);
    _verticalOffset.value = next;
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    // Action firing is handled by the raw Listener path (see _onPointerMove)
    // so curving/slanted swipes that lose the arena still trigger. Here we
    // only spring the visual offset back to rest.
    _longPressFired = false;
    _springFrom = _verticalOffset.value;
    if (_springFrom != 0) _spring.forward(from: 0);
  }

  void _onVerticalDragCancel() {
    _longPressFired = false;
    _springFrom = _verticalOffset.value;
    if (_springFrom != 0) _spring.forward(from: 0);
  }

  void _onDoubleTap() {
    if (_blocked) {
      if (WidgetResizeGestureGuard.isResizing &&
          !WidgetResizeGestureGuard.isHandlePointerActive) {
        WidgetResizeGestureGuard.requestDismiss();
      }
      return;
    }
    widget.onDoubleTap();
  }

  void _onPointerDown(PointerDownEvent e) {
    _tracks[e.pointer] = _PointerTrack(
      e.position,
      startedBlocked: _blocked,
    );
  }

  void _onPointerMove(PointerMoveEvent e) {
    final t = _tracks[e.pointer];
    if (t == null || t.fired) return;
    if (_longPressFired) return;
    final dy = e.position.dy - t.start.dy;
    // Net displacement from touch-down — robust to curved paths because we
    // ignore the intermediate trajectory entirely.
    final crossed = dy <= -_fireThreshold || dy >= _fireThreshold;
    if (!crossed) return;
    // While a widget is in edit mode any swipe must dismiss the
    // selection rather than fire onSwipeUp/onSwipeDown. We still mark
    // the track as fired so we don't keep re-broadcasting on every
    // subsequent move event for the same gesture.
    if (t.startedBlocked || _blocked) {
      t.fired = true;
      // If a resize handle is actively being dragged, this PointerMove IS the
      // resize gesture — the raw Listener sees the same pointer stream that
      // the handle's drag recognizer is consuming. Dismissing here would kill
      // edit mode the instant the user crosses 56px while sizing the widget.
      // Only treat the swipe as a dismiss request when no handle is engaged.
      if (WidgetResizeGestureGuard.isResizing &&
          !WidgetResizeGestureGuard.isHandlePointerActive) {
        WidgetResizeGestureGuard.requestDismiss();
      }
      return;
    }
    t.fired = true;
    if (dy <= -_fireThreshold) {
      widget.onSwipeUp();
    } else {
      widget.onSwipeDown();
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _tracks.remove(e.pointer);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _tracks.remove(e.pointer);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          _TolerantLongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                  _TolerantLongPressGestureRecognizer>(
            () => _TolerantLongPressGestureRecognizer(),
            (r) => r..onLongPressStart = _onLongPressStart,
          ),
          _ResponsiveVerticalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                  _ResponsiveVerticalDragGestureRecognizer>(
            () => _ResponsiveVerticalDragGestureRecognizer(),
            (r) => r
              ..onUpdate = _onVerticalDragUpdate
              ..onEnd = _onVerticalDragEnd
              ..onCancel = _onVerticalDragCancel,
          ),
          DoubleTapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
            () => DoubleTapGestureRecognizer(),
            (r) => r..onDoubleTap = _onDoubleTap,
          ),
        },
        child: ValueListenableBuilder<double>(
          valueListenable: _verticalOffset,
          child: widget.child,
          builder: (context, dy, child) {
            if (dy == 0) return child!;
            return Transform.translate(
              offset: Offset(0, dy),
              transformHitTests: false,
              child: child,
            );
          },
        ),
      ),
    );
  }
}

class _PointerTrack {
  final Offset start;
  final bool startedBlocked;
  bool fired = false;
  _PointerTrack(this.start, {required this.startedBlocked});
}

// Long-press recognizer that tolerates finger wobble both before and after
// the timeout so micro jitter doesn't silently cancel the menu trigger.
class _TolerantLongPressGestureRecognizer extends LongPressGestureRecognizer {
  _TolerantLongPressGestureRecognizer()
      : super(
          duration: const Duration(milliseconds: 500),
          postAcceptSlopTolerance: 96,
        );

  @override
  double? get preAcceptSlopTolerance => 48;
}

// Vertical drag recognizer that claims the arena sooner than the default
// kTouchSlop (~18px). A slow, deliberate upward swipe to open the drawer
// otherwise loses the arena to the PageView's horizontal recognizer on the
// slightest horizontal wobble.
class _ResponsiveVerticalDragGestureRecognizer
    extends VerticalDragGestureRecognizer {
  @override
  bool hasSufficientGlobalDistanceToAccept(
      PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) {
    return globalDistanceMoved.abs() > 8.0;
  }
}
