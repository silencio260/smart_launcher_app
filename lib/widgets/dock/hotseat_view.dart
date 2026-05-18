import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../models/folder_info.dart';
import '../../models/item_info.dart';
import '../../models/launcher_settings.dart';
import '../../models/workspace_item_info.dart';
import '../../services/drag/drag_controller.dart';
import '../../state/apps_cubit.dart';
import '../../state/settings_cubit.dart';
import '../../state/workspace_cubit.dart';
import '../folder/folder_icon.dart';
import '../folder/folder_view.dart';
import '../icons/bubble_text_view.dart';

const String kDockFolderPrefix = 'folder:';

sealed class DockItem {
  const DockItem();
}

class DockAppItem extends DockItem {
  final AppInfo app;

  const DockAppItem(this.app);
}

class DockFolderItem extends DockItem {
  final String folderId;
  final FolderInfo folder;

  const DockFolderItem({
    required this.folderId,
    required this.folder,
  });
}

class HotseatView extends StatelessWidget {
  final List<DockItem?> apps;
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
    final slotCount = settings.dockSize.clamp(0, settings.gridColumns).toInt();

    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(slotCount, (slot) {
        final item = slot < apps.length ? apps[slot] : null;
        return Flexible(
          child: _DockSlot(
            item: item,
            slot: slot,
            apps: apps,
            settings: settings,
            badgeCounts: badgeCounts,
            dragController: dragController,
            onAppTap: onAppTap,
            onAppLongPress: onAppLongPress,
          ),
        );
      }),
    );

    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) onSwipeUp();
      },
      child: settings.dockShowBackground
          ? ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: settings.dockBackgroundColor
                        .withValues(alpha: settings.dockBackgroundOpacity),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: row,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: row,
            ),
    );
  }
}

class _DockSlot extends StatelessWidget {
  final DockItem? item;
  final int slot;
  final List<DockItem?> apps;
  final LauncherSettings settings;
  final Map<String, int> badgeCounts;
  final DragController dragController;
  final void Function(AppInfo) onAppTap;
  final void Function(AppInfo) onAppLongPress;

  const _DockSlot({
    required this.item,
    required this.slot,
    required this.apps,
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
    final packages = _ensureInitialized(s.dockPackages);
    while (packages.length <= slot) {
      packages.add('');
    }
    packages[slot] = packageName;
    context.read<SettingsCubit>().update(s.copyWith(dockPackages: packages));
  }

  // Returns a mutable copy of dockPackages, pre-populated from the resolved
  // apps list when the settings list is still empty (never customized).
  List<String> _ensureInitialized(List<String> current) {
    if (current.isNotEmpty) return List<String>.from(current);
    return apps.map((item) {
      if (item is DockAppItem) return item.app.packageName;
      if (item is DockFolderItem) return '$kDockFolderPrefix${item.folderId}';
      return '';
    }).toList();
  }

  // Persists the initialized dockPackages if they were not yet saved.
  // Called on drag start so that CellLayoutView._removeDockPackage can find
  // and clear this slot even when dockPackages was still empty.
  void _initDockPackagesIfNeeded(BuildContext context) {
    final s = context.read<SettingsCubit>().state;
    if (s.dockPackages.isEmpty) {
      final packages = _ensureInitialized(s.dockPackages);
      context.read<SettingsCubit>().update(s.copyWith(dockPackages: packages));
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = item;
    final dockIconSize = settings.iconSize;
    final slotWidth = dockIconSize + 16;
    final slotHeight =
        dockIconSize + (settings.showDockLabels ? dockIconSize * 0.6 : 16);

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
            final packages = _ensureInitialized(s.dockPackages);
            while (packages.length <= payload.sourceSlot) {
              packages.add('');
            }
            packages[payload.sourceSlot] = '';
            context
                .read<SettingsCubit>()
                .update(s.copyWith(dockPackages: packages));
          }
        },
        builder: (_, candidateData, __) {
          return SizedBox(
            width: slotWidth,
            height: slotHeight,
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

    if (current is DockFolderItem) {
      return _buildFolderSlot(context, current, slotWidth, slotHeight);
    }

    final currentApp = (current as DockAppItem).app;
    final badge = badgeCounts[currentApp.packageName] ?? 0;
    final payload = DragPayload(
      item: WorkspaceItemInfo(
        id: currentApp.id,
        itemType: ItemType.application,
        packageName: currentApp.packageName,
        componentName: currentApp.appComponentName,
        title: currentApp.name,
        icon: currentApp.icon,
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
        final displacedPkg = currentApp.packageName;

        // Put incoming app into this dock slot
        _setDockSlot(context, incomingPkg);

        // Relocate the displaced app to the source location
        if (incoming.sourcePage >= 0) {
          // From workspace — put displaced app back at the source workspace slot
          final workspaceCubit = context.read<WorkspaceCubit>();
          final displacedItem = WorkspaceItemInfo(
            id: currentApp.id,
            itemType: ItemType.application,
            packageName: displacedPkg,
            componentName: currentApp.appComponentName,
            title: currentApp.name,
            icon: currentApp.icon,
          );
          workspaceCubit.addItem(
              displacedItem, incoming.sourcePage, incoming.sourceSlot);
        } else if (incoming.sourcePage == -1 && incoming.sourceSlot != slot) {
          // From a different dock slot — swap: put displaced app at source dock slot
          final s = context.read<SettingsCubit>().state;
          final packages = List<String>.from(s.dockPackages);
          while (packages.length <= incoming.sourceSlot) {
            packages.add('');
          }
          packages[incoming.sourceSlot] = displacedPkg;
          context
              .read<SettingsCubit>()
              .update(s.copyWith(dockPackages: packages));
        }
      },
      builder: (_, candidateData, __) {
        final isHovered = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: slotWidth,
          height: slotHeight,
          decoration: isHovered
              ? BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: LongPressDraggable<DragPayload>(
            data: payload,
            delay: const Duration(milliseconds: 350),
            onDragStarted: () {
              _initDockPackagesIfNeeded(context);
              dragController.startDrag(payload.item, -1, slot, Offset.zero);
            },
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
                    app: currentApp,
                    iconSize: dockIconSize,
                    showLabel: false,
                    iconShape: settings.iconShape,
                  ),
                ),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.3,
              child: BubbleTextView(
                app: currentApp,
                iconSize: dockIconSize,
                showLabel: settings.showDockLabels,
                iconShape: settings.iconShape,
                badgeCount: badge,
              ),
            ),
            child: BubbleTextView(
              app: currentApp,
              iconSize: dockIconSize,
              showLabel: settings.showDockLabels,
              iconShape: settings.iconShape,
              badgeCount: badge,
              onTap: () => onAppTap(currentApp),
              onLongPress: () => onAppLongPress(currentApp),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFolderSlot(
    BuildContext context,
    DockFolderItem current,
    double slotWidth,
    double slotHeight,
  ) {
    final folderSettings = settings.copyWith(
      showFolderLabels: settings.showDockLabels,
    );

    return DragTarget<DragPayload>(
      onWillAcceptWithDetails: (d) =>
          d.data.item is WorkspaceItemInfo &&
          (d.data.item as WorkspaceItemInfo).packageName.isNotEmpty,
      onAcceptWithDetails: (details) {
        final item = details.data.item;
        if (item is! WorkspaceItemInfo || item.packageName.isEmpty) return;
        context.read<WorkspaceCubit>().addToFolder(current.folderId, item);

        if (details.data.sourcePage >= 0) {
          context
              .read<WorkspaceCubit>()
              .removeItem(details.data.sourcePage, details.data.sourceSlot);
          context.read<WorkspaceCubit>().collapseEmptyPages();
        } else if (details.data.sourcePage == -1 &&
            details.data.sourceSlot != slot) {
          final s = context.read<SettingsCubit>().state;
          final packages = _ensureInitialized(s.dockPackages);
          while (packages.length <= details.data.sourceSlot) {
            packages.add('');
          }
          packages[details.data.sourceSlot] = '';
          context
              .read<SettingsCubit>()
              .update(s.copyWith(dockPackages: packages));
        } else if (details.data.folderId != null) {
          context
              .read<WorkspaceCubit>()
              .removeFromFolder(details.data.folderId!, item);
          details.data.onFolderDropCompleted?.call();
        }
      },
      builder: (_, candidateData, __) {
        final isHovered = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: slotWidth,
          height: slotHeight,
          decoration: isHovered
              ? BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: Center(
            child: FolderIconView(
              folder: current.folder,
              settings: folderSettings,
              onTap: () => _openFolder(context, current.folderId),
              onLongPress: () {},
            ),
          ),
        );
      },
    );
  }

  void _openFolder(BuildContext context, String folderId) {
    final overlay = Overlay.of(context);
    final workspaceCubit = context.read<WorkspaceCubit>();
    final appsCubit = context.read<AppsCubit>();
    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: workspaceCubit),
          BlocProvider.value(value: appsCubit),
        ],
        child: FolderView(
          folderId: folderId,
          folderPage: -1,
          folderSlot: slot,
          settings: settings,
          badgeCounts: badgeCounts,
          dragController: dragController,
          onClose: () {
            entry?.remove();
            entry = null;
          },
          onAppTap: (app) {
            entry?.remove();
            entry = null;
            onAppTap(app);
          },
        ),
      ),
    );
    overlay.insert(entry!);
  }
}
