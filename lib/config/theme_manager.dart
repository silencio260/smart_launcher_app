import 'package:flutter/material.dart';

/// Centralised app theme configuration.
///
/// Extracted verbatim from the previous inline `MaterialApp` themes so the
/// launcher's transparent, edge-to-edge surfaces are unchanged.
class AppTheme {
  const AppTheme._();

  static ThemeData _base(Brightness brightness) => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: brightness,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      );

  static ThemeData get light => _base(Brightness.light);

  static ThemeData get dark => _base(Brightness.dark);
}
