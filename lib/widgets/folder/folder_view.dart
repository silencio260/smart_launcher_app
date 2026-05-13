import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../models/launcher_settings.dart';
import '../../models/workspace_item_info.dart';
import '../../services/drag/drag_controller.dart';
import '../../state/apps_cubit.dart';
import '../../state/workspace_cubit.dart';
import '../icons/bubble_text_view.dart';

class FolderView extends StatefulWidget {
  final String folderId;
  final int folderPage;
  final int folderSlot;
  final LauncherSettings settings;
  final Map<String, int> badgeCounts;
  final DragController dragController;
  final void Function(AppInfo app) onAppTap;
  final VoidCallback onClose;

  const FolderView({
    super.key,
    required this.folderId,
    required this.folderPage,
    required this.folderSlot,
    required this.settings,
    required this.badgeCounts,
    required this.dragController,
    required this.onAppTap,
    required this.onClose,
  });

  @override
  State<FolderView> createState() => _FolderViewState();
}

class _FolderViewState extends State<FolderView>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late TextEditingController _titleController;
  bool _editingTitle = false;
  bool _closing = false;
  bool _dragOutAccepted = false;

  // Drag state
  bool _dragging = false;
  WorkspaceItemInfo? _draggedItem;
  // True once the dragged pointer exits the folder container's bounds.
  bool _exitedFolder = false;

  // Key for the folder content container so we can read its screen rect.
  final GlobalKey _containerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _scaleAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOutBack);
    final folder =
        context.read<WorkspaceCubit>().state.folders[widget.folderId];
    _titleController = TextEditingController(text: folder?.folderTitle ?? '');
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _animController.reverse().then((_) {
      if (mounted) widget.onClose();
    });
  }

  bool _sameFolderItem(WorkspaceItemInfo a, WorkspaceItemInfo b) {
    final aComponent = a.componentName ?? a.packageName;
    final bComponent = b.componentName ?? b.packageName;
    return a.packageName == b.packageName &&
        aComponent == bComponent &&
        a.user == b.user;
  }

  bool _containsFolderItem(
    List<WorkspaceItemInfo> items,
    WorkspaceItemInfo target,
  ) =>
      items.any((item) => _sameFolderItem(item, target));

  // Called while a drag is live on each pointer-move event.
  // Compares the global pointer position against the folder container's rect
  // and triggers the open/close animation when the pointer crosses the boundary.
  void _onPointerMove(PointerMoveEvent event) {
    // One-way latch: once the pointer exits the folder bounds during a drag,
    // stay exited for the rest of that drag.  Allowing re-entry causes a
    // rapid toggle (setState queues a rebuild, but the next pointer event
    // arrives before the frame flips, sees layout-unchanged bounds, and
    // immediately un-exits — producing a visible glitch).
    if (!_dragging || _exitedFolder) return;
    final renderBox =
        _containerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final localPos = renderBox.globalToLocal(event.position);
    final inside = (Offset.zero & renderBox.size).inflate(8).contains(localPos);

    if (!inside) {
      _exitedFolder = true;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<WorkspaceCubit, WorkspaceState>(
      listenWhen: (prev, next) {
        final wasPresent = prev.folders.containsKey(widget.folderId);
        final isPresent = next.folders.containsKey(widget.folderId);
        if (wasPresent && !isPresent) return true;

        final draggedItem = _draggedItem;
        if (!_dragging || !_exitedFolder || draggedItem == null) {
          return false;
        }

        final previousContents = prev.folders[widget.folderId]?.contents;
        final nextContents = next.folders[widget.folderId]?.contents;
        if (previousContents == null || nextContents == null) return false;

        return _containsFolderItem(previousContents, draggedItem) &&
            !_containsFolderItem(nextContents, draggedItem);
      },
      listener: (context, state) {
        if (_dragging && _exitedFolder && !_dragOutAccepted) {
          setState(() => _dragOutAccepted = true);
        }
        _close();
      },
      child: BlocBuilder<WorkspaceCubit, WorkspaceState>(
        buildWhen: (prev, next) =>
            prev.folders[widget.folderId] != next.folders[widget.folderId],
        builder: (context, workspaceState) {
          final folder = workspaceState.folders[widget.folderId];
          if (folder == null) return const SizedBox.shrink();
          final liveApps = context.watch<AppsCubit>().state.apps;

          if ((_dragging && _exitedFolder) || _dragOutAccepted) {
            return IgnorePointer(
              child: Opacity(
                opacity: 0.0,
                child: _buildFolderContent(folder.contents, liveApps),
              ),
            );
          }

          // Normal (or dragging-inside-folder) render.
          // While a drag is in progress inside the folder:
          //   • dim the backdrop to 0 so the workspace shows through
          //   • disable the tap-to-close gesture on the backdrop
          //   • keep folder content fully interactive for reorder DragTargets
          return GestureDetector(
            onTap: _dragging ? null : _close,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                color: Colors.black.withValues(alpha: _dragging ? 0.0 : 0.5),
                child: Center(
                  child: GestureDetector(
                    onTap: () {},
                    child: ScaleTransition(
                      scale: _scaleAnim,
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewInsets.bottom,
                        ),
                        child: _buildFolderContent(folder.contents, liveApps),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFolderContent(
      List<WorkspaceItemInfo> apps, List<AppInfo> liveApps) {
    return Container(
      key: _containerKey,
      width: MediaQuery.of(context).size.width * 0.82,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: BoxDecoration(
        color: Colors.grey[850]!.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Flexible(child: _buildGrid(apps, liveApps)),
          const SizedBox(height: 12),
          _buildTitle(context
                  .read<WorkspaceCubit>()
                  .state
                  .folders[widget.folderId]
                  ?.folderTitle ??
              ''),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTitle(String folderTitle) {
    if (_editingTitle) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Material(
          color: Colors.transparent,
          child: TextField(
            controller: _titleController,
            autofocus: true,
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Folder name',
              hintStyle: TextStyle(color: Colors.white38),
            ),
            onSubmitted: (title) {
              setState(() => _editingTitle = false);
              context
                  .read<WorkspaceCubit>()
                  .renameFolder(widget.folderId, title);
            },
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () {
        final folder =
            context.read<WorkspaceCubit>().state.folders[widget.folderId];
        _titleController.text = folder?.folderTitle ?? '';
        setState(() => _editingTitle = true);
      },
      child: BlocBuilder<WorkspaceCubit, WorkspaceState>(
        buildWhen: (prev, next) =>
            prev.folders[widget.folderId]?.folderTitle !=
            next.folders[widget.folderId]?.folderTitle,
        builder: (context, state) {
          final title = state.folders[widget.folderId]?.folderTitle ?? '';
          return Text(
            title.isEmpty ? 'Folder' : title,
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          );
        },
      ),
    );
  }

  Widget _buildGrid(List<WorkspaceItemInfo> apps, List<AppInfo> liveApps) {
    return GridView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.settings.folderMaxColumns,
        childAspectRatio: widget.settings.iconSize /
            (widget.settings.iconSize +
                (widget.settings.showFolderLabels
                    ? widget.settings.labelSize + 8
                    : 0) +
                8),
      ),
      itemCount: apps.length,
      itemBuilder: (context, i) {
        final item = apps[i];
        final resolvedIcon = item.icon ??
            liveApps
                .where((a) => a.packageName == item.packageName)
                .firstOrNull
                ?.icon;
        final app = AppInfo(
          id: item.id,
          packageName: item.packageName,
          appComponentName: item.componentName ?? item.packageName,
          title: item.title,
          icon: resolvedIcon,
        );
        final payload = DragPayload(
          item: item,
          sourcePage: -2,
          sourceSlot: -1,
          folderId: widget.folderId,
          folderPage: widget.folderPage,
          folderSlot: widget.folderSlot,
          onFolderDropCompleted: _close,
        );
        final iconView = BubbleTextView(
          app: app,
          iconSize: widget.settings.iconSize,
          showLabel: widget.settings.showFolderLabels,
          labelSize: widget.settings.labelSize,
          iconShape: widget.settings.iconShape,
          badgeCount: widget.badgeCounts[app.packageName] ?? 0,
        );

        return Center(
          // Per-slot DragTarget enables reordering by hovering one icon over
          // another — the same hover-to-swap interaction as the workspace grid.
          child: DragTarget<DragPayload>(
            onWillAcceptWithDetails: (d) =>
                d.data.folderId == widget.folderId &&
                d.data.item is WorkspaceItemInfo &&
                !_sameFolderItem(d.data.item as WorkspaceItemInfo, item),
            onAcceptWithDetails: (d) {
              context.read<WorkspaceCubit>().reorderFolderItem(
                    widget.folderId,
                    d.data.item as WorkspaceItemInfo,
                    item,
                  );
            },
            builder: (context, candidateData, _) {
              final isHovered = candidateData.isNotEmpty;
              return Listener(
                // Track pointer position to detect when the drag exits the
                // folder container's bounds.
                onPointerMove: _onPointerMove,
                child: LongPressDraggable<DragPayload>(
                  data: payload,
                  delay: const Duration(milliseconds: 350),
                  onDragStarted: () {
                    setState(() {
                      _dragging = true;
                      _draggedItem = item;
                      _exitedFolder = false;
                      _dragOutAccepted = false;
                    });
                    // Notify the workspace so its DragTarget overlay renders.
                    widget.dragController.startDragPayload(
                      payload,
                      Offset.zero,
                    );
                  },
                  onDragEnd: (details) {
                    if (!mounted) return;
                    final draggedItem = _draggedItem;
                    final folderContents = context
                        .read<WorkspaceCubit>()
                        .state
                        .folders[widget.folderId]
                        ?.contents;
                    final removedAfterDragOut = _exitedFolder &&
                        draggedItem != null &&
                        (folderContents == null ||
                            !_containsFolderItem(folderContents, draggedItem));
                    setState(() {
                      _dragging = removedAfterDragOut;
                      _exitedFolder = removedAfterDragOut;
                      _dragOutAccepted = removedAfterDragOut;
                      _draggedItem = null;
                    });
                    // Always release the drag lock so workspace targets hide.
                    widget.dragController.cancelDrag();
                    if (removedAfterDragOut) {
                      _close();
                    }
                    // Close only after state confirms the dragged item left
                    // this folder.  DragEnd alone is not enough because failed
                    // drops can report through this same path.
                  },
                  onDraggableCanceled: (_, __) {
                    // onDragEnd always fires too; state reset is handled there.
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
                  childWhenDragging: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: isHovered
                        ? BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          )
                        : null,
                    child: Opacity(opacity: 0.0, child: iconView),
                  ),
                  child: GestureDetector(
                    onTap: () => widget.onAppTap(app),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: isHovered
                          ? BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            )
                          : null,
                      child: iconView,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
