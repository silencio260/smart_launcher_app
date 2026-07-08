import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smart_launcher_app/core/analytics/app_events.dart';
import 'package:smart_launcher_app/core/models/app_info.dart';
import 'package:smart_launcher_app/core/models/launcher_feature.dart';
import 'package:smart_launcher_app/core/platform/feature_launch_dispatcher.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/launcher_feature_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:smart_launcher_app/core/widgets/app_menu/app_context_menu.dart';

class LauncherAppMenuItem {
  final String id;
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onSelected;

  const LauncherAppMenuItem({
    required this.id,
    required this.icon,
    required this.label,
    required this.onSelected,
    this.destructive = false,
  });
}

Future<void> showLauncherAppContextMenu(
  BuildContext context, {
  required AppInfo app,
  required Offset globalPosition,
  List<LauncherAppMenuItem> leadingItems = const [],
  List<LauncherAppMenuItem> trailingItems = const [],
  bool includeUninstall = false,
}) async {
  final settingsCubit = context.read<SettingsCubit>();
  final featureCubit = context.read<LauncherFeatureSettingsCubit>();
  final featureId = LauncherFeatureCatalog.idForApp(app);
  final canLock = featureId == null && !app.isInternalFeature;
  final isLocked = featureCubit.state.lockedApps.contains(app.packageName);
  final fallbackPosition = Offset.zero;

  final items = <LauncherAppMenuItem>[
    ...leadingItems,
    LauncherAppMenuItem(
      id: 'app_info',
      icon: Icons.info_outline,
      label: 'App info',
      onSelected: () {
        if (!context.mounted) return;
        if (featureId != null) {
          FeatureLaunchDispatcher.openFeature(context, featureId);
        } else {
          LauncherService.openAppSettings(app.packageName);
        }
      },
    ),
    LauncherAppMenuItem(
      id: 'hide',
      icon: Icons.visibility_off_outlined,
      label: 'Hide app',
      onSelected: () {
        AppAnalytics.appHiderToggle(hidden: true);
        final settings = settingsCubit.state;
        final hidden = settings.hiddenApps.toSet()..add(app.launcherKey);
        settingsCubit.update(
          settings.copyWith(hiddenApps: hidden.toList()..sort()),
        );
      },
    ),
    if (canLock)
      LauncherAppMenuItem(
        id: 'lock',
        icon: isLocked ? Icons.lock_open_outlined : Icons.lock_outline,
        label: isLocked ? 'Unlock app' : 'Lock app',
        onSelected: () => featureCubit.setAppLocked(app.packageName, !isLocked),
      ),
    ...trailingItems,
    if (includeUninstall && canLock)
      LauncherAppMenuItem(
        id: 'uninstall',
        icon: Icons.delete_outline,
        label: 'Uninstall',
        destructive: true,
        onSelected: () => LauncherService.uninstallApp(app.packageName),
      ),
  ];

  AppAnalytics.appContextMenuOpened(actionsAvailable: items.length);

  final position =
      globalPosition == Offset.zero ? fallbackPosition : globalPosition;
  final selected = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.08),
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (dialogContext, _, __) => _LauncherAppMenuOverlay(
      appName: app.name,
      globalPosition: position,
      items: items,
    ),
  );

  if (selected == null) return;
  for (final item in items) {
    if (item.id == selected) {
      item.onSelected();
      return;
    }
  }
}

class _LauncherAppMenuOverlay extends StatelessWidget {
  final String appName;
  final Offset globalPosition;
  final List<LauncherAppMenuItem> items;

  const _LauncherAppMenuOverlay({
    required this.appName,
    required this.globalPosition,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const menuW = 224.0;
    const gap = 12.0;
    final anchor = globalPosition == Offset.zero
        ? Offset(screenSize.width / 2, screenSize.height / 2)
        : globalPosition;
    final menuH = 60.0 + items.length * 44.0;
    final left =
        (anchor.dx - menuW / 2).clamp(8.0, screenSize.width - menuW - 8);
    final aboveTop = anchor.dy - menuH - gap;
    final top = (aboveTop >= 8.0 ? aboveTop : anchor.dy + gap)
        .clamp(8.0, screenSize.height - menuH - 8);

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        onPanStart: (_) => Navigator.of(context).pop(),
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: AppContextMenu(
                  title: appName,
                  actions: [
                    for (final item in items)
                      AppMenuAction(
                        icon: item.icon,
                        label: item.label,
                        destructive: item.destructive,
                        onTap: () => Navigator.of(context).pop(item.id),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
