import 'dart:async';
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
import 'home_widget_slot.dart';
import 'home_widget_stack_view.dart';

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
  int? _draggingSlot;

  // Tracks per-slot timers for app displacement during widget hover
  final Map<int, Timer> _displacementTimers = {};

  @override
  void dispose() {
    _cancelAllDisplacementTimers();
    super.dispose();
  }

  void _cancelAllDisplacementTimers() {
    for (final t in _displacementTimers.values) {
      t.cancel();
    }
    _displacementTimers.clear();
  }

  void _startDisplacementTimer(int slot, WorkspaceCubit workspace, LauncherSettings settings) {
    if (_displacementTimers.containsKey(slot)) return;
    _displacementTimers[slot] = Timer(const Duration(milliseconds: 1500), () {
      _displacementTimers.remove(slot);
      _tryDisplaceApp(slot, workspace, settings);
    });
  }

  void _cancelDisplacementTimer(int slot) {
    _displacementTimers[slot]?.cancel();
    _displacementTimers.remove(slot);
  }

  void _tryDisplaceApp(int appSlot, WorkspaceCubit workspace, LauncherSettings settings) {
    final totalSlots = settings.gridColumns * settings.gridRows;
    final adjacent = _adjacentSlots(appSlot, settings.gridColumns, totalSlots);

    for (final adj in adjacent) {
      final target = widget.page.slots[adj];
      if (target == null || target is EmptySlot) {
        workspace.moveItem(widget.pageIndex, appSlot, widget.pageIndex, adj);
        widget.dragController.recordDisplacement(widget.pageIndex, appSlot, adj);
        return;
      }
    }
    // No adjacent empty slot — widget cannot displace this app
  }

  List<int> _adjacentSlots(int slot, int cols, int total) {
    final col = slot % cols;
    final result = <int>[];
    if (col < cols - 1) result.add(slot + 1);        // right
    if (col > 0) result.add(slot - 1);               // left
    if (slot + cols < total) result.add(slot + cols); // below
    if (slot - cols >= 0) result.add(slot - cols);    // above
    return result;
  }

  void _removeDockPackage(BuildContext context, int dockSlot) {
    final settings = context.read<SettingsCubit>().state;
    final packages = List<String>.from(settings.dockPackages);
    if (dockSlot < packages.length) packages[dockSlot] = '';
    context.read<SettingsCubit>().update(settings.copyWith(dockPackages: packages));
  }

  void _onDrop(BuildContext context, DragTargetDetails<DragPayload> details, int slot) {
    // Always commit displacements on any successful drop
    widget.dragController.commitDisplacements();
    _cancelAllDisplacementTimers();

    final payload = details.data;
    final target = widget.page.slots[slot];
    final workspace = context.read<WorkspaceCubit>();

    // ── Widget drag ────────────────────────────────────────────────────────────
    if (payload.isWidget) {
      if (target is WidgetSlot || target is WidgetStackSlot) {
        // Stack the two widgets together
        workspace.createWidgetStack(
            payload.sourcePage, payload.sourceSlot, widget.pageIndex, slot);
      } else {
        // Empty slot (possibly just vacated by a displaced app)
        workspace.moveItem(
            payload.sourcePage, payload.sourceSlot, widget.pageIndex, slot);
      }
      workspace.collapseEmptyPages();
      widget.dragController.cancelDrag();
      return;
    }

    // ── Normal app/folder drag ─────────────────────────────────────────────────

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

    if (payload.sourcePage == kDrawerSourcePage) {
      final item = payload.item;
      if (item is WorkspaceItemInfo) {
        if (target is FolderSlot) {
          workspace.addToFolder(target.folderId, item);
        } else if (target is AppSlot) {
          workspace.createFolderFromExternal(item, widget.pageIndex, slot, '');
        } else {
          workspace.addItem(item, widget.pageIndex, slot);
        }
        workspace.collapseEmptyPages();
      }
      widget.dragController.cancelDrag();
      return;
    }

    if (target is FolderSlot) {
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
        if (payload.sourcePage >= 0) {
          workspace.moveItem(
              payload.sourcePage, payload.sourceSlot, widget.pageIndex, slot);
        }
      }
    } else if (target is AppSlot &&
        payload.sourcePage == widget.pageIndex &&
        payload.item is WorkspaceItemInfo) {
      workspace.createFolder(widget.pageIndex, payload.sourceSlot, slot, '');
    } else if (target is AppSlot && payload.sourcePage >= 0) {
      workspace.moveItem(
          payload.sourcePage, payload.sourceSlot, widget.pageIndex, slot);
    } else {
      if (payload.sourcePage >= 0) {
        workspace.moveItem(
            payload.sourcePage, payload.sourceSlot, widget.pageIndex, slot);
      } else if (payload.sourcePage == -1) {
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

  bool _willAccept(DragPayload payload, SlotContent? target, int slot) {
    // Reject same-slot drops
    if (payload.sourcePage == widget.pageIndex && payload.sourceSlot == slot) {
      return false;
    }
    // Widgets cannot go into folders or onto undisplaced apps
    if (payload.isWidget) {
      if (target is FolderSlot) return false;
      if (target is AppSlot) return false; // app was not displaced
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
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
          onWillAcceptWithDetails: (d) => _willAccept(d.data, content, slot),
          onAcceptWithDetails: (d) => _onDrop(context, d, slot),
          onMove: (details) {
            if (details.data.isWidget && content is AppSlot) {
              final workspace = context.read<WorkspaceCubit>();
              final settings = context.read<SettingsCubit>().state;
              _startDisplacementTimer(slot, workspace, settings);
            }
          },
          onLeave: (_) => _cancelDisplacementTimer(slot),
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
              child: _buildSlotContent(context, content, slot, appsState),
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

    if (content is WidgetSlot) {
      return _buildWidgetSlot(context, content, slot);
    }

    if (content is WidgetStackSlot) {
      return _buildWidgetStackSlot(context, content, slot);
    }

    if (content is AppSlot) {
      return _buildAppSlot(context, content, slot, appsState);
    }

    if (content is FolderSlot) {
      return _buildFolderSlot(context, content, slot, appsState);
    }

    return const SizedBox.shrink();
  }

  Widget _buildWidgetSlot(BuildContext context, WidgetSlot content, int slot) {
    final w = content.widget;
    final payload = DragPayload(
      item: WorkspaceItemInfo(
        id: w.id,
        itemType: ItemType.appWidget,
        packageName: w.providerPackage,
        componentName: w.providerClass,
        title: 'Widget',
      ),
      sourcePage: widget.pageIndex,
      sourceSlot: slot,
    );

    return LongPressDraggable<DragPayload>(
      data: payload,
      delay: const Duration(milliseconds: 350),
      onDragStarted: () {
        setState(() => _draggingSlot = slot);
        widget.dragController.startDrag(payload.item, widget.pageIndex, slot, Offset.zero);
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
          opacity: 0.8,
          child: Container(
            width: 120,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white38),
            ),
            child: const Center(
              child: Icon(Icons.widgets_outlined, color: Colors.white70, size: 36),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.25,
        child: HomeWidgetSlot(widget: w, page: widget.pageIndex, slot: slot),
      ),
      child: HomeWidgetSlot(widget: w, page: widget.pageIndex, slot: slot),
    );
  }

  Widget _buildWidgetStackSlot(
      BuildContext context, WidgetStackSlot content, int slot) {
    // Use first widget to build a representative drag payload
    final first = content.widgets.first;
    final payload = DragPayload(
      item: WorkspaceItemInfo(
        id: first.id,
        itemType: ItemType.appWidget,
        packageName: first.providerPackage,
        componentName: first.providerClass,
        title: 'Widget Stack',
      ),
      sourcePage: widget.pageIndex,
      sourceSlot: slot,
    );

    return LongPressDraggable<DragPayload>(
      data: payload,
      delay: const Duration(milliseconds: 350),
      onDragStarted: () {
        setState(() => _draggingSlot = slot);
        widget.dragController.startDrag(payload.item, widget.pageIndex, slot, Offset.zero);
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
          opacity: 0.8,
          child: Container(
            width: 120,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white38),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.widgets_outlined, color: Colors.white70, size: 28),
                  Text(
                    '${content.widgets.length}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.25,
        child: HomeWidgetStackView(
          widgets: content.widgets,
          spanX: content.spanX,
          spanY: content.spanY,
          page: widget.pageIndex,
          slot: slot,
        ),
      ),
      child: HomeWidgetStackView(
        widgets: content.widgets,
        spanX: content.spanX,
        spanY: content.spanY,
        page: widget.pageIndex,
        slot: slot,
      ),
    );
  }

  Widget _buildAppSlot(
      BuildContext context, AppSlot content, int slot, AppsState appsState) {
    final item = content.item;
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
          onLongPress: _draggingSlot == slot
              ? null
              : () {
                  final box = context.findRenderObject() as RenderBox?;
                  final center = box == null
                      ? Offset.zero
                      : box.localToGlobal(
                          Offset(box.size.width / 2, box.size.height / 2));
                  widget.onAppLongPress(app, slot, center);
                },
        ),
      ),
    );
  }

  Widget _buildFolderSlot(
      BuildContext context, FolderSlot content, int slot, AppsState appsState) {
    final folders = context.watch<WorkspaceCubit>().state.folders;
    final folder = folders[content.folderId];
    if (folder == null) return const SizedBox.shrink();

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
