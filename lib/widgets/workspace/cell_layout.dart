import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../models/folder_info.dart';
import '../../models/item_info.dart';
import '../../models/launcher_settings.dart';
import '../../models/workspace_item_info.dart';
import '../../services/drag/drag_controller.dart';
import '../../services/launcher_service.dart';
import '../../state/apps_cubit.dart';
import '../../state/settings_cubit.dart';
import '../../state/workspace_cubit.dart';
import '../folder/folder_icon.dart';
import '../folder/folder_view.dart';
import '../icons/bubble_text_view.dart';

// sourcePage == -3 means the drag originated from the app drawer (no removal needed)
const int kDrawerSourcePage = -3;

class CellLayoutView extends StatefulWidget {
  final WorkspacePage page;
  final int pageIndex;
  final LauncherSettings settings;
  final DragController dragController;
  final Map<String, int> badgeCounts;
  final void Function(AppInfo app) onAppTap;
  final void Function(AppInfo app, int slot, Offset iconCenter) onAppLongPress;

  const CellLayoutView({
    super.key,
    required this.page,
    required this.pageIndex,
    required this.settings,
    required this.dragController,
    required this.badgeCounts,
    required this.onAppTap,
    required this.onAppLongPress,
  });

  @override
  State<CellLayoutView> createState() => _CellLayoutViewState();
}

class _CellLayoutViewState extends State<CellLayoutView> {
  // Tracks which slot started a drag so we can suppress the context-menu
  // long-press callback that fires ~150ms after onDragStarted.
  int? _draggingSlot;

  void _removeDockPackage(BuildContext context, int dockSlot) {
    final settings = context.read<SettingsCubit>().state;
    final packages = List<String>.from(settings.dockPackages);
    if (dockSlot < packages.length) packages[dockSlot] = '';
    context.read<SettingsCubit>().update(settings.copyWith(dockPackages: packages));
  }

  void _onDrop(BuildContext context, DragTargetDetails<DragPayload> details, int slot) {
    final payload = details.data;
    final target = widget.page.slots[slot];
    final workspace = context.read<WorkspaceCubit>();

    // Drag originated from inside a folder — place item and remove from folder
    if (payload.folderId != null) {
      final item = payload.item;
      if (item is WorkspaceItemInfo) {
        if (target is FolderSlot) {
          workspace.addToFolder(target.folderId, item);
        } else {
          workspace.addItem(item, widget.pageIndex, slot);
        }
        workspace.removeFromFolder(payload.folderId!, item.id);
        final remaining =
            workspace.state.folders[payload.folderId!]?.contents.length ?? 0;
        if (remaining <= 1) {
          workspace.tryCollapseFolder(
              payload.folderId!, payload.folderPage, payload.folderSlot);
        }
      }
      workspace.collapseEmptyPages();
      widget.dragController.cancelDrag();
      return;
    }

    // Drag from app drawer — add to workspace, no removal needed
    if (payload.sourcePage == kDrawerSourcePage) {
      final item = payload.item;
      if (item is WorkspaceItemInfo) {
        workspace.addItem(item, widget.pageIndex, slot);
        workspace.collapseEmptyPages();
      }
      widget.dragController.cancelDrag();
      return;
    }

    if (target is FolderSlot) {
      // Only apps can be added into a folder (not nested folders)
      final item = payload.item;
      if (item is WorkspaceItemInfo && item.itemType == ItemType.application) {
        final added = workspace.addToFolder(target.folderId, item);
        if (added) {
          if (payload.sourcePage >= 0) {
            workspace.removeItem(payload.sourcePage, payload.sourceSlot);
          } else if (payload.sourcePage == -1) {
            _removeDockPackage(context, payload.sourceSlot);
          }
        }
      } else {
        // Folder dragged onto folder → move folder to the target slot instead
        if (payload.sourcePage >= 0) {
          workspace.moveItem(
              payload.sourcePage, payload.sourceSlot, widget.pageIndex, slot);
        }
      }
    } else if (target is AppSlot &&
        payload.sourcePage == widget.pageIndex &&
        payload.item is WorkspaceItemInfo) {
      // Same-page app-on-app → create folder at the target slot
      workspace.createFolder(
          widget.pageIndex, payload.sourceSlot, slot, '');
    } else if (target is AppSlot && payload.sourcePage >= 0) {
      // Cross-page app-on-app → move (overwrites target)
      workspace.moveItem(
          payload.sourcePage, payload.sourceSlot, widget.pageIndex, slot);
    } else {
      // Empty slot — move from workspace or place from dock
      if (payload.sourcePage >= 0) {
        workspace.moveItem(
            payload.sourcePage, payload.sourceSlot, widget.pageIndex, slot);
      } else if (payload.sourcePage == -1) {
        // From dock
        final item = payload.item;
        if (item is WorkspaceItemInfo) {
          workspace.addItem(item, widget.pageIndex, slot);
          _removeDockPackage(context, payload.sourceSlot);
        }
      }
    }

    workspace.collapseEmptyPages();
    widget.dragController.cancelDrag();
  }

  @override
  Widget build(BuildContext context) {
    // Watch AppsCubit so icons refresh when apps finish loading
    final appsState = context.watch<AppsCubit>().state;
    final totalSlots = widget.settings.gridColumns * widget.settings.gridRows;

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.settings.gridColumns,
        childAspectRatio: widget.settings.iconSize /
            (widget.settings.iconSize +
                (widget.settings.showLabels
                    ? widget.settings.labelSize + 8
                    : 0) +
                8),
      ),
      itemCount: totalSlots,
      itemBuilder: (context, slot) {
        final content = widget.page.slots[slot];
        return DragTarget<DragPayload>(
          onWillAcceptWithDetails: (details) =>
              details.data.sourcePage != widget.pageIndex ||
              details.data.sourceSlot != slot,
          onAcceptWithDetails: (details) => _onDrop(context, details, slot),
          builder: (context, candidateData, _) {
            final isHovered = candidateData.isNotEmpty;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: isHovered
                  ? BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    )
                  : null,
              child:
                  _buildSlotContent(context, content, slot, appsState),
            );
          },
        );
      },
    );
  }

  Widget _buildSlotContent(
    BuildContext context,
    SlotContent? content,
    int slot,
    AppsState appsState,
  ) {
    if (content == null || content is EmptySlot) {
      return const SizedBox.shrink();
    }

    if (content is AppSlot) {
      final item = content.item;

      // Always prefer the live icon from AppsCubit (survives restarts);
      // fall back to cached bytes only if AppsCubit hasn't loaded yet.
      final liveApp = appsState.apps
          .where((a) => a.packageName == item.packageName)
          .firstOrNull;
      final app = AppInfo(
        id: item.id,
        packageName: item.packageName,
        appComponentName:
            item.componentName ?? liveApp?.appComponentName ?? item.packageName,
        title: item.title ?? liveApp?.name,
        icon: liveApp?.icon ?? item.icon,
      );

      final badge = widget.badgeCounts[item.packageName] ?? 0;
      final payload =
          DragPayload(item: item, sourcePage: widget.pageIndex, sourceSlot: slot);

      return Center(
        child: LongPressDraggable<DragPayload>(
          data: payload,
          delay: const Duration(milliseconds: 350),
          onDragStarted: () {
            // Record which slot is being dragged BEFORE the long-press
            // callback fires (~150ms later at the system threshold).
            setState(() => _draggingSlot = slot);
            widget.dragController.startDrag(item, widget.pageIndex, slot, Offset.zero);
          },
          onDragEnd: (_) {
            setState(() => _draggingSlot = null);
            widget.dragController.cancelDrag();
          },
          onDraggableCanceled: (_, __) {
            setState(() => _draggingSlot = null);
            widget.dragController.cancelDrag();
          },
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.85,
              child: Transform.scale(
                scale: 1.15,
                child: BubbleTextView(
                  app: app,
                  iconSize: widget.settings.iconSize,
                  showLabel: false,
                  iconShape: widget.settings.iconShape,
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: BubbleTextView(
              app: app,
              iconSize: widget.settings.iconSize,
              showLabel: widget.settings.showLabels,
              labelSize: widget.settings.labelSize,
              iconShape: widget.settings.iconShape,
              badgeCount: badge,
            ),
          ),
          child: BubbleTextView(
            app: app,
            iconSize: widget.settings.iconSize,
            showLabel: widget.settings.showLabels,
            labelSize: widget.settings.labelSize,
            iconShape: widget.settings.iconShape,
            badgeCount: badge,
            onTap: () => widget.onAppTap(app),
            // Only fire context menu when drag is NOT in progress for this slot.
            // onDragStarted fires at 350ms; onLongPress fires at ~500ms,
            // so by the time this callback runs _draggingSlot is already set.
            onLongPress: _draggingSlot == slot
                ? null
                : () {
                    final box = context.findRenderObject() as RenderBox?;
                    final center = box == null
                        ? Offset.zero
                        : box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
                    widget.onAppLongPress(app, slot, center);
                  },
          ),
        ),
      );
    }

    if (content is FolderSlot) {
      final folders = context.watch<WorkspaceCubit>().state.folders;
      final folder = folders[content.folderId];
      if (folder == null) return const SizedBox.shrink();

      // Resolve live icons for folder preview icons
      final resolvedFolder = _resolveFolderIcons(folder, appsState);

      return Center(
        child: LongPressDraggable<DragPayload>(
          data: DragPayload(
            item: WorkspaceItemInfo(
              id: folder.id,
              itemType: ItemType.folder,
              packageName: '',
              title: folder.folderTitle,
            ),
            sourcePage: widget.pageIndex,
            sourceSlot: slot,
          ),
          delay: const Duration(milliseconds: 350),
          onDragStarted: () {
            setState(() => _draggingSlot = slot);
            widget.dragController.startDrag(
                WorkspaceItemInfo(
                  id: folder.id,
                  itemType: ItemType.folder,
                  packageName: '',
                  title: folder.folderTitle,
                ),
                widget.pageIndex,
                slot,
                Offset.zero);
          },
          onDragEnd: (_) {
            setState(() => _draggingSlot = null);
            widget.dragController.cancelDrag();
          },
          onDraggableCanceled: (_, __) {
            setState(() => _draggingSlot = null);
            widget.dragController.cancelDrag();
          },
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.85,
              child: Transform.scale(
                scale: 1.15,
                child: FolderIconView(
                  folder: resolvedFolder,
                  settings: widget.settings,
                  onTap: () {},
                  onLongPress: () {},
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: FolderIconView(
              folder: resolvedFolder,
              settings: widget.settings,
              onTap: () {},
              onLongPress: () {},
            ),
          ),
          child: FolderIconView(
            folder: resolvedFolder,
            settings: widget.settings,
            badgeCount: 0,
            onTap: () => _openFolder(context, content.folderId, slot),
            onLongPress: _draggingSlot == slot ? () {} : () {},
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// Replaces WorkspaceItemInfo.icon=null with live icons from AppsCubit
  /// so folder preview icons are visible after a restart.
  FolderInfo _resolveFolderIcons(FolderInfo folder, AppsState appsState) {
    final resolved = folder.contents.map((item) {
      if (item.icon != null) return item;
      final live = appsState.apps
          .where((a) => a.packageName == item.packageName)
          .firstOrNull;
      if (live == null) return item;
      return WorkspaceItemInfo(
        id: item.id,
        itemType: item.itemType,
        packageName: item.packageName,
        componentName: item.componentName ?? live.appComponentName,
        title: item.title ?? live.name,
        icon: live.icon,
      );
    }).toList();
    return FolderInfo(
      id: folder.id,
      folderTitle: folder.folderTitle,
      contents: resolved,
      cellX: folder.cellX,
      cellY: folder.cellY,
      screenId: folder.screenId,
    );
  }

  void _openFolder(BuildContext context, String folderId, int slot) {
    final overlay = Overlay.of(context);
    final workspaceCubit = context.read<WorkspaceCubit>();
    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (overlayCtx) => BlocProvider.value(
        value: workspaceCubit,
        child: FolderView(
          folderId: folderId,
          folderPage: widget.pageIndex,
          folderSlot: slot,
          settings: widget.settings,
          badgeCounts: widget.badgeCounts,
          onClose: () {
            entry?.remove();
            entry = null;
          },
          onAppTap: (app) {
            entry?.remove();
            entry = null;
            LauncherService.launchApp(app.packageName);
          },
        ),
      ),
    );
    overlay.insert(entry!);
  }
}
