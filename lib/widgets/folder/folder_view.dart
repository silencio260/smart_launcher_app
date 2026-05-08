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
  final void Function(AppInfo app) onAppTap;
  final VoidCallback onClose;

  const FolderView({
    super.key,
    required this.folderId,
    required this.folderPage,
    required this.folderSlot,
    required this.settings,
    required this.badgeCounts,
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
      if (mounted) widget.onClose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<WorkspaceCubit, WorkspaceState>(
      listenWhen: (prev, next) {
        final wasPresent = prev.folders.containsKey(widget.folderId);
        final isPresent = next.folders.containsKey(widget.folderId);
        return wasPresent && !isPresent;
      },
      listener: (context, state) => _close(),
      child: BlocBuilder<WorkspaceCubit, WorkspaceState>(
        buildWhen: (prev, next) =>
            prev.folders[widget.folderId] != next.folders[widget.folderId],
        builder: (context, workspaceState) {
          final folder = workspaceState.folders[widget.folderId];
          if (folder == null) return const SizedBox.shrink();
          final liveApps = context.watch<AppsCubit>().state.apps;

          // While dragging out: keep draggables alive but hide UI.
          // Use AbsorbPointer(false) so events pass through to workspace DragTargets.
          if (_draggingOut) {
            return AbsorbPointer(
              absorbing: false,
              child: Opacity(
                opacity: 0.0,
                child: Center(child: _buildGrid(folder.contents, liveApps)),
              ),
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
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewInsets.bottom,
                        ),
                        child: Container(
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
                              Flexible(child: _buildGrid(folder.contents, liveApps)),
                              const SizedBox(height: 12),
                              _buildTitle(folder.folderTitle),
                              const SizedBox(height: 16),
                            ],
                          ),
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
        child: Material(
          color: Colors.transparent,
          child: TextField(
            controller: _titleController,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Folder name',
              hintStyle: TextStyle(color: Colors.white38),
            ),
            onSubmitted: (title) {
              setState(() => _editingTitle = false);
              context.read<WorkspaceCubit>().renameFolder(widget.folderId, title);
            },
          ),
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

  Widget _buildGrid(List<WorkspaceItemInfo> apps, List<AppInfo> liveApps) {
    return GridView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.settings.folderMaxColumns,
        childAspectRatio: widget.settings.iconSize /
            (widget.settings.iconSize +
                (widget.settings.showFolderLabels ? widget.settings.labelSize + 8 : 0) +
                8),
      ),
      itemCount: apps.length,
      itemBuilder: (context, i) {
        final item = apps[i];
        final resolvedIcon = item.icon ??
            liveApps.where((a) => a.packageName == item.packageName).firstOrNull?.icon;
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
          child: LongPressDraggable<DragPayload>(
            data: payload,
            delay: const Duration(milliseconds: 350),
            onDragStarted: () => setState(() => _draggingOut = true),
            onDragEnd: (_) {
              if (mounted) setState(() => _draggingOut = false);
              _close();
            },
            onDraggableCanceled: (_, __) {
              if (mounted) setState(() => _draggingOut = false);
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
