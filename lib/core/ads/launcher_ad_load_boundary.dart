import 'dart:async';
import 'package:flutter/material.dart';
import 'package:genrevibes_ads/genrevibes_ads.dart';

/// Owns the request deadline and a single delayed retry for a mounted slot.
class LauncherAdLoadBoundary extends StatefulWidget {
  const LauncherAdLoadBoundary({
    super.key,
    required this.placement,
    required this.active,
    required this.canRetry,
    required this.builder,
  });
  final AdPlacement placement;
  final bool active;
  final bool Function() canRetry;
  final Widget Function(
    int attempt,
    bool Function(AdEvent) onEvent,
    void Function(String) onFailure,
  )
  builder;

  @override
  State<LauncherAdLoadBoundary> createState() => _LauncherAdLoadBoundaryState();
}

class _LauncherAdLoadBoundaryState extends State<LauncherAdLoadBoundary> {
  Timer? _timer;
  int _attempt = 1;
  bool _failed = false;
  bool _exhausted = false;
  bool _loaded = false;
  bool _requested = false;
  DateTime? _deadline;
  Duration _remaining = const Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    if (widget.active) _startDeadline();
  }

  @override
  void didUpdateWidget(LauncherAdLoadBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active || _loaded || _exhausted) return;
    if (!widget.active) {
      if (_deadline != null) {
        final remaining = _deadline!.difference(DateTime.now());
        _remaining = remaining.isNegative ? Duration.zero : remaining;
      }
      _timer?.cancel();
      _deadline = null;
    } else if (!_requested) {
      _startDeadline();
    } else {
      _schedule();
    }
  }

  void _log(String message) => debugPrint(
    'LauncherInlineAd [${widget.placement.id}] attempt=$_attempt $message',
  );

  void _startDeadline() {
    _requested = true;
    _remaining = const Duration(seconds: 30);
    _log('loading');
    _schedule();
  }

  void _schedule() {
    if (!widget.active || _loaded || _exhausted) return;
    _timer?.cancel();
    _deadline = DateTime.now().add(_remaining);
    _timer = Timer(_remaining, () {
      _deadline = null;
      if (!mounted || !widget.active) return;
      if (!_failed) {
        _fail(_attempt, 'load_timeout_30s');
      } else if (widget.canRetry()) {
        setState(() {
          _attempt++;
          _failed = false;
        });
        _startDeadline();
      } else {
        _log('retry blocked by policy');
        setState(() => _exhausted = true);
      }
    });
  }

  void _fail(int attempt, String message) {
    if (!mounted || attempt != _attempt || _failed || _exhausted) return;
    _timer?.cancel();
    _deadline = null;
    _log('failed: $message');
    setState(() {
      _failed = true;
      _loaded = false;
      _exhausted = _attempt >= 2;
    });
    if (!_exhausted) {
      _remaining = const Duration(seconds: 30);
      _schedule();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_exhausted || !_requested) return const SizedBox.shrink();
    // A failed view is removed immediately, cancelling stale callbacks, and
    // remains collapsed during the bounded backoff.
    if (_failed) {
      return const SizedBox.shrink();
    }
    final attempt = _attempt;
    // Android platform views must be painted to finish creating their surface.
    // Offstage-until-loaded caused a circular wait. Keep a small, clipped slot
    // during loading, then reveal the full card when assets are ready.
    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: _loaded ? 1 : 0.14,
        child: IgnorePointer(
          ignoring: !_loaded,
          child: widget.builder(attempt, (event) {
            if (!mounted || attempt != _attempt || _failed || _exhausted) {
              return false;
            }
            if (event.type == AdEventType.loaded) {
              _timer?.cancel();
              _deadline = null;
              setState(() => _loaded = true);
            }
            _log(event.type.name);
            return true;
          }, (message) => _fail(attempt, message)),
        ),
      ),
    );
  }
}
