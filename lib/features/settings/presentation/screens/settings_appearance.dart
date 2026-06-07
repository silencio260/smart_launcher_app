import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';

class SettingsAppearance extends StatelessWidget {
  final Widget child;

  const SettingsAppearance({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, LauncherSettings>(
      buildWhen: (previous, next) =>
          previous.settingsBackgroundMode != next.settingsBackgroundMode ||
          previous.themeMode != next.themeMode,
      builder: (context, settings) {
        final brightness = _brightnessFor(context, settings);
        final color = _backgroundFor(context, settings, brightness);
        final theme = _settingsTheme(context, brightness);
        return Theme(
          data: theme,
          child: Container(
            color: color,
            child: child,
          ),
        );
      },
    );
  }
}

MaterialPageRoute<T> settingsRoute<T>(Widget child) {
  return MaterialPageRoute<T>(
    builder: (_) => SettingsAppearance(child: child),
  );
}

Brightness _brightnessFor(BuildContext context, LauncherSettings settings) {
  switch (settings.settingsBackgroundMode) {
    case SettingsBackgroundMode.black:
      return Brightness.dark;
    case SettingsBackgroundMode.white:
      return Brightness.light;
    case SettingsBackgroundMode.system:
      return MediaQuery.platformBrightnessOf(context);
    case SettingsBackgroundMode.theme:
    case SettingsBackgroundMode.wallpaper:
      return Theme.of(context).brightness;
  }
}

Color _backgroundFor(
  BuildContext context,
  LauncherSettings settings,
  Brightness brightness,
) {
  switch (settings.settingsBackgroundMode) {
    case SettingsBackgroundMode.black:
      return Colors.black;
    case SettingsBackgroundMode.white:
      return Colors.white;
    case SettingsBackgroundMode.system:
    case SettingsBackgroundMode.theme:
      return brightness == Brightness.dark ? Colors.black : Colors.white;
    case SettingsBackgroundMode.wallpaper:
      return Colors.transparent;
  }
}

ThemeData _settingsTheme(BuildContext context, Brightness brightness) {
  final base = Theme.of(context);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: base.colorScheme.primary,
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: colorScheme,
    brightness: brightness,
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: colorScheme.outlineVariant,
  );
}
