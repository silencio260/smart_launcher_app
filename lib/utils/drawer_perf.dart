import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'debug_flags.dart';

/// Drawer performance logger gated by [DebugFlags.drawerPerfLogs].
///
/// Emits `DrawerPerf` lines to logcat / debug console with a session id
/// (incremented on each open) and a wall-time millisecond timestamp.
/// Pair [beginSession] / [endSession] with drawer open / close so the
/// frame timings observer is only active while the drawer is on screen.
class DrawerPerf {
  static final Stopwatch _wall = Stopwatch()..start();
  static TimingsCallback? _timingsCallback;
  static int _sessionCounter = 0;
  static int? _activeSession;
  static bool _globalTimingsInstalled = false;

  static int get sessionId => _activeSession ?? 0;
  static bool get active => _activeSession != null;

  /// Install a process-wide frame timings observer that logs every frame's
  /// build/raster cost while [DebugFlags.drawerPerfLogs] is on. Call from
  /// app startup after the flag is hydrated from settings; cheap no-op if
  /// the flag is off. Lets us see per-frame numbers outside the drawer
  /// (e.g. Settings scroll, home PageView scroll).
  static void installGlobalTimings() {
    if (_globalTimingsInstalled) return;
    if (!DebugFlags.drawerPerfLogs) return;
    _globalTimingsInstalled = true;
    SchedulerBinding.instance.addTimingsCallback(_onGlobalFrameTimings);
  }

  /// Begin a logging session (drawer opened). Installs the frame timings
  /// observer. Idempotent — calling twice without [endSession] is a no-op.
  static void beginSession() {
    if (!DebugFlags.drawerPerfLogs) return;
    if (_activeSession != null) return;
    _sessionCounter += 1;
    _activeSession = _sessionCounter;
    _timingsCallback = _onFrameTimings;
    SchedulerBinding.instance.addTimingsCallback(_timingsCallback!);
  }

  /// End the logging session (drawer closed). Removes the frame observer.
  static void endSession() {
    final cb = _timingsCallback;
    if (cb != null) {
      SchedulerBinding.instance.removeTimingsCallback(cb);
      _timingsCallback = null;
    }
    _activeSession = null;
  }

  /// Emit a single instant event. Cheap no-op when the flag is off.
  static void event(String name, {Map<String, Object?>? extra}) {
    if (!DebugFlags.drawerPerfLogs) return;
    final tMs = _wall.elapsedMicroseconds / 1000.0;
    final session = _activeSession ?? 0;
    final buf = StringBuffer()
      ..write('DrawerPerf s=')
      ..write(session)
      ..write(' t=')
      ..write(tMs.toStringAsFixed(2))
      ..write(' ')
      ..write(name);
    if (extra != null) {
      for (final entry in extra.entries) {
        buf
          ..write(' ')
          ..write(entry.key)
          ..write('=')
          ..write(entry.value);
      }
    }
    debugPrint(buf.toString());
  }

  static void _onFrameTimings(List<FrameTiming> timings) {
    if (!DebugFlags.drawerPerfLogs || _activeSession == null) return;
    for (final t in timings) {
      final buildMs = t.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = t.rasterDuration.inMicroseconds / 1000.0;
      final totalMs = t.totalSpan.inMicroseconds / 1000.0;
      event('frame', extra: {
        'buildMs': buildMs.toStringAsFixed(2),
        'rasterMs': rasterMs.toStringAsFixed(2),
        'totalMs': totalMs.toStringAsFixed(2),
      });
    }
  }

  /// Global per-frame logger. Always emits when the flag is on, regardless
  /// of whether a drawer session is active. Only logs frames that miss the
  /// 16.67ms budget to keep logcat readable while still surfacing jank.
  ///
  /// Breakdown:
  ///   vsyncMs   = vsync target -> build start (UI thread starvation)
  ///   buildMs   = build start  -> build end   (Dart UI thread work)
  ///   gpuWaitMs = build end    -> raster start (handoff / GPU back-pressure)
  ///   rasterMs  = raster start -> raster end  (GPU work + HC sync)
  static void _onGlobalFrameTimings(List<FrameTiming> timings) {
    if (!DebugFlags.drawerPerfLogs) return;
    for (final t in timings) {
      final totalMs = t.totalSpan.inMicroseconds / 1000.0;
      if (totalMs < 17.0) continue;
      final vsyncMs = t.vsyncOverhead.inMicroseconds / 1000.0;
      final buildMs = t.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = t.rasterDuration.inMicroseconds / 1000.0;
      final gpuWaitMs =
          (totalMs - vsyncMs - buildMs - rasterMs).clamp(0.0, double.infinity);
      final tMs = _wall.elapsedMicroseconds / 1000.0;
      debugPrint(
        'DrawerPerf JANK t=${tMs.toStringAsFixed(2)} '
        'vsyncMs=${vsyncMs.toStringAsFixed(2)} '
        'buildMs=${buildMs.toStringAsFixed(2)} '
        'gpuWaitMs=${gpuWaitMs.toStringAsFixed(2)} '
        'rasterMs=${rasterMs.toStringAsFixed(2)} '
        'totalMs=${totalMs.toStringAsFixed(2)}',
      );
    }
  }
}

/// Wraps a child render object and logs layout / paint durations via
/// [DrawerPerf]. When [DebugFlags.drawerPerfLogs] is off this collapses to
/// a plain `super.performLayout` / `super.paint` passthrough.
class PerfProbe extends SingleChildRenderObjectWidget {
  final String label;
  final bool measureLayout;
  final bool measurePaint;

  const PerfProbe({
    super.key,
    required this.label,
    this.measureLayout = false,
    this.measurePaint = true,
    required Widget super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) => RenderPerfProbe(
        label: label,
        measureLayout: measureLayout,
        measurePaint: measurePaint,
      );

  @override
  void updateRenderObject(BuildContext context, RenderPerfProbe renderObject) {
    renderObject
      ..label = label
      ..measureLayout = measureLayout
      ..measurePaint = measurePaint;
  }
}

class RenderPerfProbe extends RenderProxyBox {
  String label;
  bool measureLayout;
  bool measurePaint;
  bool _firstLayout = true;
  bool _firstPaint = true;

  RenderPerfProbe({
    required this.label,
    required this.measureLayout,
    required this.measurePaint,
  });

  @override
  void performLayout() {
    if (!measureLayout || !DebugFlags.drawerPerfLogs) {
      super.performLayout();
      return;
    }
    final sw = Stopwatch()..start();
    super.performLayout();
    sw.stop();
    DrawerPerf.event('$label.layout', extra: {
      'durationMs': (sw.elapsedMicroseconds / 1000.0).toStringAsFixed(2),
      'first': _firstLayout,
    });
    _firstLayout = false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!measurePaint || !DebugFlags.drawerPerfLogs) {
      super.paint(context, offset);
      return;
    }
    final sw = Stopwatch()..start();
    super.paint(context, offset);
    sw.stop();
    DrawerPerf.event('$label.paint', extra: {
      'durationMs': (sw.elapsedMicroseconds / 1000.0).toStringAsFixed(2),
      'first': _firstPaint,
    });
    _firstPaint = false;
  }
}
