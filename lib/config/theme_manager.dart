import 'package:flutter/material.dart';

/// Centralised app theme configuration.
///
/// Extracted verbatim from the previous inline `MaterialApp` themes so the
/// launcher's transparent, edge-to-edge surfaces are unchanged.
class AppTheme {
  const AppTheme._();

  static const _darkScheme = ColorScheme.dark(
    primary: Colors.white,
    onPrimary: Colors.black,
    secondary: Colors.white,
    onSecondary: Colors.black,
    tertiary: Colors.white,
    onTertiary: Colors.black,
    surface: Colors.black,
    onSurface: Colors.white,
    surfaceContainerHighest: Color(0xFF2A2A2D),
    onSurfaceVariant: Color(0xFFE2E2E6),
    outline: Color(0xFF8E8E93),
    outlineVariant: Color(0xFF3A3A3C),
    inverseSurface: Colors.white,
    onInverseSurface: Colors.black,
    inversePrimary: Colors.black,
    surfaceTint: Colors.transparent,
  );

  static const _lightScheme = ColorScheme.light(
    primary: Colors.black,
    onPrimary: Colors.white,
    secondary: Colors.black,
    onSecondary: Colors.white,
    tertiary: Colors.black,
    onTertiary: Colors.white,
    surface: Colors.white,
    onSurface: Colors.black,
    surfaceContainerHighest: Color(0xFFE8E8ED),
    onSurfaceVariant: Color(0xFF3A3A3C),
    outline: Color(0xFF6E6E73),
    outlineVariant: Color(0xFFD1D1D6),
    inverseSurface: Colors.black,
    onInverseSurface: Colors.white,
    inversePrimary: Colors.white,
    surfaceTint: Colors.transparent,
  );

  static ColorScheme schemeFor(Brightness brightness) =>
      brightness == Brightness.dark ? _darkScheme : _lightScheme;

  static ThemeData _base(Brightness brightness) {
    final scheme = schemeFor(brightness);
    final isDark = brightness == Brightness.dark;
    final active = isDark ? Colors.white : Colors.black;
    final inactive = isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73);
    final inactiveTrack =
        isDark ? const Color(0xFF2A2A2D) : const Color(0xFFD1D1D6);

    return ThemeData(
      colorScheme: scheme,
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? active : inactive,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? inactive : inactiveTrack,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? active : null,
        ),
        checkColor:
            WidgetStateProperty.all(isDark ? Colors.black : Colors.white),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? active : inactive,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: active,
        thumbColor: active,
        inactiveTrackColor: inactiveTrack,
        overlayColor: active.withValues(alpha: 0.12),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: active),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: active,
        selectionColor: active.withValues(alpha: 0.28),
        selectionHandleColor: active,
      ),
    );
  }

  static ThemeData get light => _base(Brightness.light);

  static ThemeData get dark => _base(Brightness.dark);
}
