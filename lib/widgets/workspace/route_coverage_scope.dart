import 'package:flutter/material.dart';

/// RouteObserver for the launcher's home route. Registered on MaterialApp so
/// HomeScreen can flip [RouteCoverageScope] whenever a route is pushed on top
/// (Settings, widget picker, etc.).
final RouteObserver<PageRoute<dynamic>> homeRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

/// Marks the workspace subtree as "covered by another route". Widget-host
/// views read this to drop their `AndroidView`s while the launcher is behind
/// Settings or any other pushed page. Hybrid composition of the live
/// AppWidgetHostViews otherwise keeps costing per-frame work even when the
/// home screen is fully obscured, which surfaces as scroll jank on the page
/// on top. The native side pools AppWidgetHostView instances by appWidgetId
/// (see WidgetHostViewRegistry), so re-creating on uncover reuses the cached
/// host instead of re-binding to system_server / re-running CFMS setup.
class RouteCoverageScope extends InheritedNotifier<ValueNotifier<bool>> {
  const RouteCoverageScope({
    super.key,
    required ValueNotifier<bool> super.notifier,
    required super.child,
  });

  static bool isCovered(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<RouteCoverageScope>();
    return scope?.notifier?.value ?? false;
  }
}
