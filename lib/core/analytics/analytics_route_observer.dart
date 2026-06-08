import 'package:flutter/widgets.dart';

import 'app_events.dart';

/// Logs a screen view whenever a named route is pushed/popped-back-to.
///
/// Registered on `MaterialApp.navigatorObservers`. Most mini-app screens are
/// `Navigator.push`ed with a `RouteSettings(name: ...)`, so this covers them
/// automatically. Anonymous routes (no name) are ignored to avoid noise.
class AnalyticsRouteObserver extends NavigatorObserver {
  void _track(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) return;
    AppAnalytics.screenView(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _track(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _track(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _track(newRoute);
  }
}
