import 'package:flutter/material.dart';
import 'package:smart_launcher_app/core/ads/launcher_ads.dart';
import 'package:smart_launcher_app/core/ads/launcher_banner_ad.dart';
import 'package:smart_launcher_app/features/settings/presentation/screens/settings_appearance.dart';

/// Owns one banner for the lifetime of the Settings section. Routes replace
/// only the area above it, leaving the SDK view and its refresh cycle alive.
class LauncherSettingsSection extends StatefulWidget {
  const LauncherSettingsSection({super.key, required this.child});

  final Widget child;

  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SettingsSectionScope>() !=
      null;

  @override
  State<LauncherSettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<LauncherSettingsSection> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => SettingsAppearance(
    child: _SettingsSectionScope(
      child: Column(
        children: [
          Expanded(
            child: NavigatorPopHandler<Object?>(
              onPopWithResult: (result) => _navigator.currentState?.pop(result),
              child: Navigator(
                key: _navigator,
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  settings: const RouteSettings(name: 'settings_root'),
                  builder: (_) => widget.child,
                ),
              ),
            ),
          ),
          const LauncherBannerAd(
            placement: LauncherAdPlacements.settingsBanner,
          ),
        ],
      ),
    ),
  );
}

class _SettingsSectionScope extends InheritedWidget {
  const _SettingsSectionScope({required super.child});

  @override
  bool updateShouldNotify(_SettingsSectionScope oldWidget) => false;
}
