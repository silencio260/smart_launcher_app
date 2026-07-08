import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/features/apps/presentation/bloc/apps_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/icon_shape_picker_screen.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/settings_appearance.dart';

class GeneralSettingsScreen extends StatelessWidget {
  const GeneralSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('General')),
      body: BlocBuilder<SettingsCubit, LauncherSettings>(
        builder: (context, s) {
          final cubit = context.read<SettingsCubit>();
          return ListView(
            children: [
              _SectionHeader('Appearance'),
              ListTile(
                title: const Text('Theme'),
                subtitle: Text(_themeLabel(s.themeMode)),
                leading: const Icon(Icons.dark_mode_outlined),
                onTap: () => _pickTheme(context, cubit, s),
              ),
              ListTile(
                title: const Text('Settings background'),
                subtitle: Text(_settingsBackgroundLabel(
                  s.settingsBackgroundMode,
                )),
                leading: const Icon(Icons.contrast_outlined),
                onTap: () => _pickSettingsBackground(context, cubit, s),
              ),
              ListTile(
                title: const Text('Icon Shape'),
                subtitle: Text(s.iconShape.replaceAll('_', ' ')),
                leading: const Icon(Icons.category_outlined),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final shape = await Navigator.push<String>(
                    context,
                    settingsRoute(IconShapePickerScreen(current: s.iconShape)),
                  );
                  if (shape != null) cubit.update(s.copyWith(iconShape: shape));
                },
              ),
              SwitchListTile(
                title: const Text('Themed Icons'),
                subtitle: const Text('Match icons to wallpaper colors'),
                secondary: const Icon(Icons.palette_outlined),
                value: s.themedIconsEnabled,
                onChanged: (v) =>
                    cubit.update(s.copyWith(themedIconsEnabled: v)),
              ),
              _SectionHeader('Notification Badges'),
              SwitchListTile(
                title: const Text('Show Badges'),
                subtitle:
                    const Text('Requires notification access permission'),
                secondary: const Icon(Icons.notifications_outlined),
                value: s.notificationBadgesEnabled,
                onChanged: (v) async {
                  cubit.update(s.copyWith(notificationBadgesEnabled: v));
                  final apps = context.read<AppsCubit>();
                  apps.setBadgesEnabled(v);
                  if (v && !await apps.isNotificationAccessGranted()) {
                    await apps.requestNotificationAccess();
                  }
                },
              ),
              SwitchListTile(
                title: const Text('Show Count'),
                subtitle: const Text('Number inside badge dot'),
                secondary: const Icon(Icons.format_list_numbered),
                value: s.badgeShowCount,
                onChanged: s.notificationBadgesEnabled
                    ? (v) => cubit.update(s.copyWith(badgeShowCount: v))
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }

  String _themeLabel(ThemeMode2 m) => switch (m) {
        ThemeMode2.system => 'Follow system',
        ThemeMode2.light => 'Light',
        ThemeMode2.dark => 'Dark',
      };

  String _settingsBackgroundLabel(SettingsBackgroundMode mode) =>
      switch (mode) {
        SettingsBackgroundMode.black => 'Black',
        SettingsBackgroundMode.white => 'White',
        SettingsBackgroundMode.system => 'Follow system',
        SettingsBackgroundMode.theme => 'Follow launcher theme',
        SettingsBackgroundMode.wallpaper => 'Use wallpaper',
      };

  void _pickTheme(
      BuildContext context, SettingsCubit cubit, LauncherSettings s) {
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Theme'),
        children: ThemeMode2.values
            .map((m) => RadioListTile<ThemeMode2>(
                  title: Text(_themeLabel(m)),
                  value: m,
                  groupValue: s.themeMode,
                  onChanged: (v) {
                    if (v != null) cubit.update(s.copyWith(themeMode: v));
                    Navigator.pop(context);
                  },
                ))
            .toList(),
      ),
    );
  }

  void _pickSettingsBackground(
    BuildContext context,
    SettingsCubit cubit,
    LauncherSettings s,
  ) {
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Settings background'),
        children: SettingsBackgroundMode.values
            .map((mode) => RadioListTile<SettingsBackgroundMode>(
                  title: Text(_settingsBackgroundLabel(mode)),
                  value: mode,
                  groupValue: s.settingsBackgroundMode,
                  onChanged: (value) {
                    if (value != null) {
                      cubit.update(
                        s.copyWith(settingsBackgroundMode: value),
                      );
                    }
                    Navigator.pop(context);
                  },
                ))
            .toList(),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
