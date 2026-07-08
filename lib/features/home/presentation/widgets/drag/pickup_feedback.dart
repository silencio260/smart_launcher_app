import 'package:flutter/material.dart';

/// Animated wrapper for `LongPressDraggable.feedback` widgets.
///
/// Plays a two-phase "pop" on pickup: the icon scales up from 1.0 to
/// [peakScale] (the "lift"), then settles to [targetScale]. Opacity fades in
/// over the first portion so the feedback doesn't blink into existence.
///
/// For app icons, use [targetScale] < 1.0 (default 0.85) so the draggable
/// visibly shrinks below the resting tile. For widgets, use [targetScale]
/// == 1.0 (no net size change) with a smaller [peakScale].
class PickupFeedback extends StatefulWidget {
  final Widget child;
  final double peakScale;
  final double targetScale;
  final double opacity;
  final Duration duration;

  const PickupFeedback({
    super.key,
    required this.child,
    this.peakScale = 1.2,
    this.targetScale = 0.85,
    this.opacity = 0.95,
    this.duration = const Duration(milliseconds: 280),
  });

  @override
  State<PickupFeedback> createState() => _PickupFeedbackState();
}

class _PickupFeedbackState extends State<PickupFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.0, end: widget.peakScale)
          .chain(CurveTween(curve: Curves.easeOutQuad)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: widget.peakScale, end: widget.targetScale)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 65,
    ),
  ]).animate(_controller);

  late final Animation<double> _opacity = Tween<double>(
    begin: 0.0,
    end: widget.opacity,
  ).animate(CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
  ));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, inner) {
          return Opacity(
            opacity: _opacity.value,
            child: Transform.scale(
              scale: _scale.value,
              child: inner,
            ),
          );
        },
      ),
    );
  }
}
