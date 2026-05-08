import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../models/launcher_settings.dart';
import '../../models/workspace_item_info.dart';
import '../../services/drag/drag_controller.dart';
import '../../state/workspace_cubit.dart';
import '../icons/bubble_text_view.dart';

class FolderView extends StatefulWidget {
  final String folderId;
  final int folderPage;
  final int folderSlot;
  final LauncherSettings settings;
  final Map<String, int> badgeCounts;
  final void Function(AppInfo app) onAppTap;

  const FolderView({
    super.key,
    required this.folderId,
    required this.folderPage,
    required this.folderSlot,
    required this.settings,
    required this.badgeCounts,
    required this.onAppTap,
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
  bool _draggingOut = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _scaleAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOutBack);
    final folder = context.read<WorkspaceCubit>().state.folders[widget.folderId];
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
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<WorkspaceCubit, WorkspaceState>(
      listenWhen: (prev, next) {
        // Auto-close when folder is removed (collapsed to app or deleted)
        final wasPresent = prev.folders.containsKey(widget.folderId);
        final isPresent = next.folders.containsKey(widget.folderId);
        return wasPresent && !isPresent;
      },
      listener: (context, state) => _close(),
      child: BlocBuilder<WorkspaceCubit, WorkspaceState>(
        buildWhen: (prev, next) =>
            prev.folders[widget.folderId] != next.folders[widget.folderId],
        builder: (context, state) {
          final folder = state.folders[widget.folderId];
          if (folder == null) return const SizedBox.shrink();

          // While dragging out: hide all UI but keep draggable items in tree
          if (_draggingOut) {
            return Opacity(
              opacity: 0.0,
              child: Center(child: _buildGrid(folder.contents)),
            );
          }

          return GestureDetector(
            onTap: _close,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: Center(
                  child: GestureDetector(
                    onTap: () {},
                    child: ScaleTransition(
                      scale: _scaleAnim,
                      child: Container(
                        width: MediaQuery.of(context).size.width * 0.8,
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[900]!.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 16),
                            _buildTitle(folder.folderTitle),
                            const SizedBox(height: 8),
                            Flexible(child: _buildGrid(folder.contents)),
                            const SizedBox(height: 16),
                          ],
                        ),
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

  Widget _buildTitle(String folderTitle) {
    if (_editingTitle) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: TextField(
          controller: _titleController,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(border: InputBorder.none),
          onSubmitted: (title) {
            setState(() => _editingTitle = false);
            context.read<WorkspaceCubit>().renameFolder(widget.folderId, title);
          },
        ),
      );
    }
    return GestureDetector(
      onTap: () {
        final folder = context.read<WorkspaceCubit>().state.folders[widget.folderId];
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
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          );
        },
      ),
    );
  }

  Widget _buildGrid(List<WorkspaceItemInfo> apps) {
    return GridView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.settings.folderMaxColumns,
        childAspectRatio: widget.settings.drawerIconSize /
            (widget.settings.drawerIconSize +
                (widget.settings.showFolderLabels ? widget.settings.labelSize + 8 : 0) +
                8),
      ),
      itemCount: apps.length,
      itemBuilder: (context, i) {
        final item = apps[i];
        final app = AppInfo(
          id: item.id,
          packageName: item.packageName,
          appComponentName: item.componentName ?? item.packageName,
          title: item.title,
          icon: item.icon,
        );
        final payload = DragPayload(
          item: item,
          sourcePage: -2,
          sourceSlot: -1,
          folderId: widget.folderId,
          folderPage: widget.folderPage,
          folderSlot: widget.folderSlot,
        );
        final iconView = BubbleTextView(
          app: app,
          iconSize: widget.settings.drawerIconSize,
          showLabel: widget.settings.showFolderLabels,
          labelSize: widget.settings.labelSize,
          iconShape: widget.settings.iconShape,
          badgeCount: widget.badgeCounts[app.packageName] ?? 0,
        );
        return Center(
          child: LongPressDraggable<DragPayload>(
            data: payload,
            delay: const Duration(milliseconds: 350),
            onDragStarted: () => setState(() => _draggingOut = true),
            onDragEnd: (_) {
              // Close folder after drag ends (success or cancel)
              if (mounted) setState(() => _draggingOut = false);
              _close();
            },
            feedback: Material(
              color: Colors.transparent,
              child: Opacity(
                opacity: 0.85,
                child: Transform.scale(
                  scale: 1.15,
                  child: BubbleTextView(
                    app: app,
                    iconSize: widget.settings.drawerIconSize,
                    showLabel: false,
                    iconShape: widget.settings.iconShape,
                  ),
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.0, child: iconView),
            child: GestureDetector(
              onTap: () => widget.onAppTap(app),
              child: iconView,
            ),
          ),
        );
      },
    );
  }

}
