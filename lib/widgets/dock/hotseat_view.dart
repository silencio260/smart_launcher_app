import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/app_info.dart';
import '../../models/item_info.dart';
import '../../models/launcher_settings.dart';
import '../../models/workspace_item_info.dart';
import '../../services/drag/drag_controller.dart';
import '../../state/workspace_cubit.dart';
import '../icons/bubble_text_view.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class HotseatView extends StatelessWidget {
  final List<AppInfo> apps;
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
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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

  @override
  Widget build(BuildContext context) {
    final current = app;
    if (current == null) {
      return DragTarget<DragPayload>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (details) {
          final payload = details.data;
          context.read<WorkspaceCubit>().removeItem(payload.sourcePage, payload.sourceSlot);
          // Dock is settings-managed; just remove from workspace so user can pin via settings
        },
        builder: (_, candidateData, __) {
          return SizedBox(
            width: settings.dockIconSize + 16,
            height: settings.dockIconSize + (settings.showDockLabels ? 28 : 16),
            child: candidateData.isNotEmpty
                ? Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
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
      onWillAcceptWithDetails: (d) => d.data.sourcePage != -1 || d.data.sourceSlot != slot,
      onAcceptWithDetails: (details) {
        final incoming = details.data;
        context.read<WorkspaceCubit>().removeItem(incoming.sourcePage, incoming.sourceSlot);
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
            onDragStarted: () => dragController.startDrag(
              payload.item, -1, slot, Offset.zero,
            ),
            onDragEnd: (_) => dragController.cancelDrag(),
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
