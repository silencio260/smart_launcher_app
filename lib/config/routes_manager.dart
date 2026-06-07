import 'package:flutter/material.dart';
import 'package:smart_launcher_app/features/home/presentation/screens/home_screen.dart';

/// Named route constants.
///
/// The launcher surface itself is the `home:` of the app and most in-app
/// navigation (settings, mini-apps) is done via `Navigator.push` with widgets
/// that need live `BuildContext`/Cubit access, so those are not forced through
/// named routes. This class is the single place to add named routes as flows
/// are migrated to them.
class Routes {
  Routes._();

  static const String home = '/';
}

/// Central route generator wired into `MaterialApp.onGenerateRoute`.
class AppRouter {
  const AppRouter._();

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case Routes.home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      default:
        return null;
    }
  }
}
