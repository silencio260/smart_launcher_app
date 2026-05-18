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
    if (!_longPressFired && !_blocked) {
      final v = d.primaryVelocity ?? 0;
      if (v < -300) {
        widget.onSwipeUp();
      } else if (v > 300) {
        widget.onSwipeDown();
      }
    }
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
    if (_blocked) return;
    widget.onDoubleTap();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        _TolerantLongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
                _TolerantLongPressGestureRecognizer>(
          () => _TolerantLongPressGestureRecognizer(),
          (r) => r..onLongPressStart = _onLongPressStart,
        ),
        VerticalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<
            VerticalDragGestureRecognizer>(
          () => VerticalDragGestureRecognizer(),
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
    );
  }
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
