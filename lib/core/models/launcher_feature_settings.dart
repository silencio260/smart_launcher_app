import 'package:equatable/equatable.dart';

class LauncherFeatureSettings extends Equatable {
  final bool overlayMenusEnabled;
  final bool afterCallEnabled;
  final bool installUninstallAssistantEnabled;
  final List<String> lockedApps;

  const LauncherFeatureSettings({
    this.overlayMenusEnabled = false,
    this.afterCallEnabled = false,
    this.installUninstallAssistantEnabled = false,
    this.lockedApps = const [],
  });

  LauncherFeatureSettings copyWith({
    bool? overlayMenusEnabled,
    bool? afterCallEnabled,
    bool? installUninstallAssistantEnabled,
    List<String>? lockedApps,
  }) {
    return LauncherFeatureSettings(
      overlayMenusEnabled: overlayMenusEnabled ?? this.overlayMenusEnabled,
      afterCallEnabled: afterCallEnabled ?? this.afterCallEnabled,
      installUninstallAssistantEnabled: installUninstallAssistantEnabled ??
          this.installUninstallAssistantEnabled,
      lockedApps: lockedApps ?? this.lockedApps,
    );
  }

  @override
  List<Object?> get props => [
        overlayMenusEnabled,
        afterCallEnabled,
        installUninstallAssistantEnabled,
        lockedApps,
      ];
}
