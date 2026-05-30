import 'package:equatable/equatable.dart';

class LauncherFeatureSettings extends Equatable {
  final bool overlayMenusEnabled;
  final bool afterCallEnabled;
  final bool installAssistantEnabled;
  final bool promptOnInstall;
  final bool cleanupOnUninstall;
  final List<String> lockedApps;

  const LauncherFeatureSettings({
    this.overlayMenusEnabled = false,
    this.afterCallEnabled = false,
    this.installAssistantEnabled = true,
    this.promptOnInstall = true,
    this.cleanupOnUninstall = true,
    this.lockedApps = const [],
  });

  LauncherFeatureSettings copyWith({
    bool? overlayMenusEnabled,
    bool? afterCallEnabled,
    bool? installAssistantEnabled,
    bool? promptOnInstall,
    bool? cleanupOnUninstall,
    List<String>? lockedApps,
  }) {
    return LauncherFeatureSettings(
      overlayMenusEnabled: overlayMenusEnabled ?? this.overlayMenusEnabled,
      afterCallEnabled: afterCallEnabled ?? this.afterCallEnabled,
      installAssistantEnabled:
          installAssistantEnabled ?? this.installAssistantEnabled,
      promptOnInstall: promptOnInstall ?? this.promptOnInstall,
      cleanupOnUninstall: cleanupOnUninstall ?? this.cleanupOnUninstall,
      lockedApps: lockedApps ?? this.lockedApps,
    );
  }

  @override
  List<Object?> get props => [
        overlayMenusEnabled,
        afterCallEnabled,
        installAssistantEnabled,
        promptOnInstall,
        cleanupOnUninstall,
        lockedApps,
      ];
}
