import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../models/folder_info.dart';
import '../../models/launcher_settings.dart';
import '../../state/workspace_cubit.dart';
import '../icons/bubble_text_view.dart';

class FolderView extends StatefulWidget {
  final FolderInfo folder;
  final String folderId;
  final LauncherSettings settings;
  final Map<String, int> badgeCounts;
  final void Function(AppInfo app) onAppTap;

  const FolderView({
    super.key,
    required this.folder,
    required this.folderId,
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

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _scaleAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOutBack);
    _titleController = TextEditingController(text: widget.folder.folderTitle);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _close() {
    _animController.reverse().then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _close,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          color: Colors.black.withValues(alpha: 0.5),
          child: Center(
            child: GestureDetector(
              onTap: () {}, // absorb taps inside folder
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
                      _buildTitle(),
                      const SizedBox(height: 8),
                      Flexible(child: _buildGrid()),
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
  }

  Widget _buildTitle() {
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
      onTap: () => setState(() => _editingTitle = true),
      child: Text(
        widget.folder.folderTitle.isEmpty ? 'Folder' : widget.folder.folderTitle,
        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildGrid() {
    final apps = widget.folder.contents;
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
        return Center(
          child: BubbleTextView(
            app: app,
            iconSize: widget.settings.drawerIconSize,
            showLabel: widget.settings.showFolderLabels,
            labelSize: widget.settings.labelSize,
            iconShape: widget.settings.iconShape,
            badgeCount: widget.badgeCounts[app.packageName] ?? 0,
            onTap: () => widget.onAppTap(app),
            onLongPress: () => _showItemMenu(context, app, item.id),
          ),
        );
      },
    );
  }

  void _showItemMenu(BuildContext context, AppInfo app, int itemId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[900]!.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline, color: Colors.white70),
              title: Text('Remove ${app.name} from folder',
                  style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                context
                    .read<WorkspaceCubit>()
                    .removeFromFolder(widget.folderId, itemId);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
