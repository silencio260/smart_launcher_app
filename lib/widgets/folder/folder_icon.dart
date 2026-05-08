import 'package:flutter/material.dart';
import '../../models/folder_info.dart';
import '../../models/launcher_settings.dart';
import '../icons/shaped_icon.dart';
import '../icons/dot_renderer.dart';

class FolderIconView extends StatelessWidget {
  final FolderInfo folder;
  final LauncherSettings settings;
  final int badgeCount;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const FolderIconView({
    super.key,
    required this.folder,
    required this.settings,
    this.badgeCount = 0,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final size = settings.iconSize;
    // Samsung-style: larger squircle radius, more breathing room for mini icons
    final miniSize = size * 0.33;
    final padding = size * 0.12;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: settings.folderColor,
                  borderRadius: BorderRadius.circular(size * 0.30),
                ),
                child: Padding(
                  padding: EdgeInsets.all(padding),
                  child: _buildIconGrid(miniSize),
                ),
              ),
              if (badgeCount > 0)
                DotRenderer(count: badgeCount, iconSize: size),
            ],
          ),
          if (settings.showFolderLabels) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: size + 8,
              child: Text(
                folder.folderTitle.isEmpty ? 'Folder' : folder.folderTitle,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: settings.labelSize,
                  shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIconGrid(double miniSize) {
    final count = folder.contents.length;
    if (count == 0) {
      return const SizedBox.shrink();
    }
    if (count == 1) {
      // Single icon centered
      return Center(
        child: ShapedIcon(
          iconBytes: folder.contents[0].icon,
          shape: settings.iconShape,
          size: miniSize * 1.4,
        ),
      );
    }
    // 2x2 grid for 2-4 icons; show up to 4
    return GridView.count(
      crossAxisCount: 2,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 3,
      crossAxisSpacing: 3,
      children: [
        ...folder.contents.take(4).map((item) => ShapedIcon(
              iconBytes: item.icon,
              shape: settings.iconShape,
              size: miniSize,
            )),
        ...List.generate(
          (4 - count).clamp(0, 4),
          (_) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}
