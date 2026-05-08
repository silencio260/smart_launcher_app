import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../models/item_info.dart';
import '../../models/launcher_settings.dart';
import '../../models/workspace_item_info.dart';
import '../../services/drag/drag_controller.dart';
import '../../state/settings_cubit.dart';
import '../../state/workspace_cubit.dart';
import '../icons/bubble_text_view.dart';

class HotseatView extends StatelessWidget {
  final List<AppInfo?> apps;
  final LauncherSettings settings;
  final Map<String, int> badgeCounts;
  final DragController dragController;
  final VoidCallback onSwipeUp;
  final void Function(AppInfo app) onAppTap;
  final void Function(AppInfo app) onAppLongPress;

  const HotseatView({
    super.key,
    required this.apps,
    required this.settings,
    required this.badgeCounts,
    required this.dragController,
    required this.onSwipeUp,
    required this.onAppTap,
    required this.onAppLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (!settings.showDock) return const SizedBox.shrink();

    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) onSwipeUp();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: settings.dockShowBackground
                  ? settings.dockBackgroundColor
                      .withValues(alpha: settings.dockBackgroundOpacity)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(settings.dockSize, (slot) {
                final app = slot < apps.length ? apps[slot] : null;
                return _DockSlot(
                  app: app,
                  slot: slot,
                  settings: settings,
                  badgeCounts: badgeCounts,
                  dragController: dragController,
                  onAppTap: onAppTap,
                  onAppLongPress: onAppLongPress,
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockSlot extends StatelessWidget {
  final AppInfo? app;
  final int slot;
  final LauncherSettings settings;
  final Map<String, int> badgeCounts;
  final DragController dragController;
  final void Function(AppInfo) onAppTap;
  final void Function(AppInfo) onAppLongPress;

  const _DockSlot({
    required this.app,
    required this.slot,
    required this.settings,
    required this.badgeCounts,
    required this.dragController,
    required this.onAppTap,
    required this.onAppLongPress,
  });

  // Writes `packageName` at position `slot` in dockPackages, expanding the
  // list with empty strings as needed.
  void _setDockSlot(BuildContext context, String packageName) {
    final s = context.read<SettingsCubit>().state;
    final packages = List<String>.from(s.dockPackages);
    while (packages.length <= slot) { packages.add(''); }
    packages[slot] = packageName;
    context.read<SettingsCubit>().update(s.copyWith(dockPackages: packages));
  }

  @override
  Widget build(BuildContext context) {
    final current = app;

    if (current == null) {
      // Empty dock slot — accepts drops from workspace or other dock slots.
      return DragTarget<DragPayload>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (details) {
          final payload = details.data;
          final pkg = (payload.item is WorkspaceItemInfo)
              ? (payload.item as WorkspaceItemInfo).packageName
              : '';
          if (pkg.isEmpty) return;

          _setDockSlot(context, pkg);

          // Remove from workspace source if dragged from workspace
          if (payload.sourcePage >= 0) {
            context
                .read<WorkspaceCubit>()
                .removeItem(payload.sourcePage, payload.sourceSlot);
            context.read<WorkspaceCubit>().collapseEmptyPages();
          }
          // If dragged from another dock slot, clear that slot
          if (payload.sourcePage == -1 && payload.sourceSlot != slot) {
            final s = context.read<SettingsCubit>().state;
            final packages = List<String>.from(s.dockPackages);
            if (payload.sourceSlot < packages.length) {
              packages[payload.sourceSlot] = '';
            }
            context
                .read<SettingsCubit>()
                .update(s.copyWith(dockPackages: packages));
          }
        },
        builder: (_, candidateData, __) {
          return SizedBox(
            width: settings.dockIconSize + 16,
            height: settings.dockIconSize +
                (settings.showDockLabels ? 28 : 16),
            child: candidateData.isNotEmpty
                ? Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  )
                : null,
          );
        },
      );
    }

    final badge = badgeCounts[current.packageName] ?? 0;
    final payload = DragPayload(
      item: WorkspaceItemInfo(
        id: current.id,
        itemType: ItemType.application,
        packageName: current.packageName,
        componentName: current.appComponentName,
        title: current.name,
        icon: current.icon,
      ),
      sourcePage: -1, // -1 = dock source
      sourceSlot: slot,
    );

    return DragTarget<DragPayload>(
      // Accept anything except itself
      onWillAcceptWithDetails: (d) =>
          d.data.sourcePage != -1 || d.data.sourceSlot != slot,
      onAcceptWithDetails: (details) {
        final incoming = details.data;
        final incomingPkg = (incoming.item is WorkspaceItemInfo)
            ? (incoming.item as WorkspaceItemInfo).packageName
            : '';
        if (incomingPkg.isEmpty) return;

        // Save the displaced app before overwriting this slot
        final displacedPkg = current.packageName;

        // Put incoming app into this dock slot
        _setDockSlot(context, incomingPkg);

        // Relocate the displaced app to the source location
        if (incoming.sourcePage >= 0) {
          // From workspace — put displaced app back at the source workspace slot
          final workspaceCubit = context.read<WorkspaceCubit>();
          final displacedItem = WorkspaceItemInfo(
            id: current.id,
            itemType: ItemType.application,
            packageName: displacedPkg,
            componentName: current.appComponentName,
            title: current.name,
            icon: current.icon,
          );
          workspaceCubit.addItem(displacedItem, incoming.sourcePage, incoming.sourceSlot);
        } else if (incoming.sourcePage == -1 && incoming.sourceSlot != slot) {
          // From a different dock slot — swap: put displaced app at source dock slot
          final s = context.read<SettingsCubit>().state;
          final packages = List<String>.from(s.dockPackages);
          while (packages.length <= incoming.sourceSlot) { packages.add(''); }
          packages[incoming.sourceSlot] = displacedPkg;
          context.read<SettingsCubit>().update(s.copyWith(dockPackages: packages));
        }
      },
      builder: (_, candidateData, __) {
        final isHovered = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: isHovered
              ? BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: LongPressDraggable<DragPayload>(
            data: payload,
            delay: const Duration(milliseconds: 350),
            onDragStarted: () =>
                dragController.startDrag(payload.item, -1, slot, Offset.zero),
            onDragEnd: (details) {
              dragController.cancelDrag();
            },
            feedback: Material(
              color: Colors.transparent,
              child: Opacity(
                opacity: 0.85,
                child: Transform.scale(
                  scale: 1.15,
                  child: BubbleTextView(
                    app: current,
                    iconSize: settings.dockIconSize,
                    showLabel: false,
                    iconShape: settings.iconShape,
                  ),
                ),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.3,
              child: BubbleTextView(
                app: current,
                iconSize: settings.dockIconSize,
                showLabel: settings.showDockLabels,
                iconShape: settings.iconShape,
                badgeCount: badge,
              ),
            ),
            child: BubbleTextView(
              app: current,
              iconSize: settings.dockIconSize,
              showLabel: settings.showDockLabels,
              iconShape: settings.iconShape,
              badgeCount: badge,
              onTap: () => onAppTap(current),
              onLongPress: () => onAppLongPress(current),
            ),
          ),
        );
      },
    );
  }
}
