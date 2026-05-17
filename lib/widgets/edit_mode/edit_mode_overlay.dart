import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/folder_info.dart';
import '../../models/launcher_settings.dart';
import '../../models/workspace_item_info.dart';
import '../../state/workspace_cubit.dart';
import '../icons/shaped_icon.dart';

class EditModeOverlay extends StatefulWidget {
  final LauncherSettings settings;
  final Map<int, Uint8List> initialWidgetSnapshots;
  final VoidCallback onDismiss;
  final VoidCallback onWallpaper;
  final VoidCallback onThemes;
  final VoidCallback onWidgets;
  final VoidCallback onSettings;

  const EditModeOverlay({
    super.key,
    required this.settings,
    this.initialWidgetSnapshots = const {},
    required this.onDismiss,
    required this.onWallpaper,
    required this.onThemes,
    required this.onWidgets,
    required this.onSettings,
  });

  @override
  State<EditModeOverlay> createState() => _EditModeOverlayState();
}

class _EditModeOverlayState extends State<EditModeOverlay>
    with SingleTickerProviderStateMixin {
  static const double _viewportFraction = 0.84;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late PageController _pageController;
  int _displayedPage = 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    final initialPage = context.read<WorkspaceCubit>().state.currentPage;
    _displayedPage = initialPage;
    _pageController = PageController(
      initialPage: initialPage,
      viewportFraction: _viewportFraction,
    );
    _pageController.addListener(_handlePageScroll);
  }

  @override
  void dispose() {
    _pageController.removeListener(_handlePageScroll);
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _handlePageScroll() {
    if (!_pageController.hasClients) return;
    final page = _pageController.page;
    if (page == null) return;
    final rounded = page.round();
    if (rounded != _displayedPage) {
      setState(() => _displayedPage = rounded);
    }
  }

  void _dismiss() {
    _animController.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  void _commitCurrentPage() {
    final cubit = context.read<WorkspaceCubit>();
    if (_displayedPage != cubit.state.currentPage &&
        _displayedPage < cubit.state.pages.length) {
      cubit.setCurrentPage(_displayedPage);
    }
  }

  void _addPage() {
    final cubit = context.read<WorkspaceCubit>();
    cubit.addPage();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.animateToPage(
        cubit.state.pages.length - 1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _confirmRemovePage(int pageIndex) async {
    final cubit = context.read<WorkspaceCubit>();
    if (cubit.state.pages.length <= 1) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove page?'),
        content: const Text(
          'Items on this page will be removed from your home screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final newLength = cubit.state.pages.length - 1;
    cubit.removePage(pageIndex);
    if (!mounted) return;
    // Keep the overlay open. Adjust the displayed page so it stays in range
    // and the PageView doesn't jump unexpectedly.
    final target = _displayedPage.clamp(0, (newLength - 1).clamp(0, newLength));
    setState(() => _displayedPage = target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: GestureDetector(
        onTap: _dismiss,
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
          child: BlocBuilder<WorkspaceCubit, WorkspaceState>(
            builder: (context, state) {
              final activeIndex =
                  _displayedPage.clamp(0, state.pages.length - 1);
              return Column(
                children: [
                  const SizedBox(height: 6),
                  const _HomeBadge(),
                  const SizedBox(height: 10),
                  _RemoveDropTarget(
                    enabled: state.pages.length > 1,
                    onAccept: _confirmRemovePage,
                  ),
                  const SizedBox(height: 10),
                  const _HairlineDivider(),
                  const SizedBox(height: 12),
                  Expanded(child: _buildPagesRow(state)),
                  const SizedBox(height: 12),
                  _PageDots(
                    count: state.pages.length,
                    active: activeIndex,
                    onAddPage: _addPage,
                  ),
                  const SizedBox(height: 22),
                  _buildBottomBar(),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPagesRow(WorkspaceState state) {
    return GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: PageView.builder(
        controller: _pageController,
        itemCount: state.pages.length,
        onPageChanged: (i) => setState(() => _displayedPage = i),
        itemBuilder: (context, i) {
          return _PageCard(
            pageIndex: i,
            page: state.pages[i],
            folders: state.folders,
            settings: widget.settings,
            widgetSnapshots: widget.initialWidgetSnapshots,
            onTap: () {
              context.read<WorkspaceCubit>().setCurrentPage(i);
              _dismiss();
            },
          );
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    return GestureDetector(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _BottomBarItem(
              icon: Icons.wallpaper_outlined,
              label: 'Wallpaper\nand style',
              onTap: () {
                _commitCurrentPage();
                widget.onWallpaper();
              },
            ),
            _BottomBarItem(
              icon: Icons.format_paint_outlined,
              label: 'Themes',
              onTap: () {
                _commitCurrentPage();
                widget.onThemes();
              },
            ),
            _BottomBarItem(
              icon: Icons.widgets_outlined,
              label: 'Widgets',
              onTap: () {
                _commitCurrentPage();
                widget.onWidgets();
              },
            ),
            _BottomBarItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () {
                _commitCurrentPage();
                widget.onSettings();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Top home indicator ──────────────────────────────────────────────────────

class _HomeBadge extends StatelessWidget {
  const _HomeBadge();

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.home_outlined,
      color: Colors.white.withValues(alpha: 0.9),
      size: 22,
    );
  }
}

// ─── Trash drop target (no pill, no label) ───────────────────────────────────

class _RemoveDropTarget extends StatelessWidget {
  final bool enabled;
  final ValueChanged<int> onAccept;

  const _RemoveDropTarget({required this.enabled, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => enabled,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (_, candidate, __) {
        final hovering = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: hovering
                ? Colors.red.withValues(alpha: 0.85)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            hovering ? Icons.delete_forever : Icons.delete_outline,
            color: enabled
                ? Colors.white
                : Colors.white.withValues(alpha: 0.35),
            size: 24,
          ),
        );
      },
    );
  }
}

class _HairlineDivider extends StatelessWidget {
  const _HairlineDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 28),
      color: Colors.white.withValues(alpha: 0.18),
    );
  }
}

// ─── Page dots + trailing "+" ────────────────────────────────────────────────

class _PageDots extends StatelessWidget {
  final int count;
  final int active;
  final VoidCallback onAddPage;

  const _PageDots({
    required this.count,
    required this.active,
    required this.onAddPage,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: i == active ? 8 : 6,
              height: i == active ? 8 : 6,
              decoration: BoxDecoration(
                color: i == active
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
            ),
          ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: onAddPage,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Icon(
              Icons.add,
              color: Colors.white.withValues(alpha: 0.9),
              size: 18,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Page card (chromeless, draggable, tappable) ─────────────────────────────

class _PageCard extends StatelessWidget {
  final int pageIndex;
  final WorkspacePage page;
  final Map<String, FolderInfo> folders;
  final LauncherSettings settings;
  final Map<int, Uint8List> widgetSnapshots;
  final VoidCallback onTap;

  const _PageCard({
    required this.pageIndex,
    required this.page,
    required this.folders,
    required this.settings,
    required this.widgetSnapshots,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final preview = _PagePreview(
      page: page,
      folders: folders,
      settings: settings,
      widgetSnapshots: widgetSnapshots,
    );
    final framed = _PageFrame(child: preview);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: LongPressDraggable<int>(
        data: pageIndex,
        delay: const Duration(milliseconds: 280),
        feedback: _DragFeedback(
          width: MediaQuery.of(context).size.width * 0.55,
          child: _PagePreview(
            page: page,
            folders: folders,
            settings: settings,
            widgetSnapshots: widgetSnapshots,
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: framed),
        child: GestureDetector(
          onTap: onTap,
          child: framed,
        ),
      ),
    );
  }
}

class _PageFrame extends StatelessWidget {
  final Widget child;
  const _PageFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.55),
          width: 1.4,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(6),
      child: child,
    );
  }
}

class _DragFeedback extends StatelessWidget {
  final double width;
  final Widget child;

  const _DragFeedback({required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: width,
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.9),
                width: 1.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(10),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ─── Page preview (icons with labels, folders, widget previews) ──────────────

class _PagePreview extends StatelessWidget {
  final WorkspacePage page;
  final Map<String, FolderInfo> folders;
  final LauncherSettings settings;
  final Map<int, Uint8List> widgetSnapshots;

  const _PagePreview({
    required this.page,
    required this.folders,
    required this.settings,
    required this.widgetSnapshots,
  });

  @override
  Widget build(BuildContext context) {
    final cols = settings.gridColumns;
    final rows = settings.gridRows;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 4.0;
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final cellW = (w - gap * (cols + 1)) / cols;
        final cellH = (h - gap * (rows + 1)) / rows;
        if (cellW <= 0 || cellH <= 0) return const SizedBox.shrink();

        final children = <Widget>[];
        page.slots.forEach((slot, content) {
          if (content is EmptySlot) return;
          final row = slot ~/ cols;
          final col = slot % cols;
          if (row >= rows || col >= cols) return;

          final (spanX, spanY) = switch (content) {
            WidgetSlot(:final widget) => (
                widget.spanX.clamp(1, cols).toInt(),
                widget.spanY.clamp(1, rows).toInt(),
              ),
            WidgetStackSlot(:final spanX, :final spanY) => (
                spanX.clamp(1, cols).toInt(),
                spanY.clamp(1, rows).toInt(),
              ),
            _ => (1, 1),
          };

          final left = gap + col * (cellW + gap);
          final top = gap + row * (cellH + gap);
          final width = spanX * cellW + (spanX - 1) * gap;
          final height = spanY * cellH + (spanY - 1) * gap;

          children.add(Positioned(
            left: left,
            top: top,
            width: width,
            height: height,
            child: _buildSlot(content, cellW, cellH),
          ));
        });

        return Stack(children: children);
      },
    );
  }

  Widget _buildSlot(SlotContent content, double cellW, double cellH) {
    final iconSize = (cellW * 0.58).clamp(14.0, 36.0);
    switch (content) {
      case AppSlot(:final item):
        return _AppTile(
          item: item,
          iconSize: iconSize,
          shape: settings.iconShape,
          showLabel: settings.showLabels,
        );
      case FolderSlot(:final folderId):
        final folder = folders[folderId];
        return _FolderTile(
          folder: folder,
          iconSize: iconSize,
          shape: settings.iconShape,
          showLabel: settings.showLabels,
        );
      case WidgetSlot(:final widget):
        return _WidgetTile(previewImage: widgetSnapshots[widget.appWidgetId]);
      case WidgetStackSlot(:final widgets):
        final first = widgets
            .map((w) => widgetSnapshots[w.appWidgetId])
            .firstWhere((b) => b != null, orElse: () => null);
        return _WidgetTile(previewImage: first, isStack: true);
      case EmptySlot():
        return const SizedBox.shrink();
    }
  }
}

class _AppTile extends StatelessWidget {
  final WorkspaceItemInfo item;
  final double iconSize;
  final String shape;
  final bool showLabel;

  const _AppTile({
    required this.item,
    required this.iconSize,
    required this.shape,
    required this.showLabel,
  });

  @override
  Widget build(BuildContext context) {
    final label = item.title ?? '';
    final fontSize = (iconSize * 0.3).clamp(7.5, 10.0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        ShapedIcon(iconBytes: item.icon, shape: shape, size: iconSize),
        if (showLabel && label.isNotEmpty) ...[
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                height: 1.1,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FolderTile extends StatelessWidget {
  final FolderInfo? folder;
  final double iconSize;
  final String shape;
  final bool showLabel;

  const _FolderTile({
    required this.folder,
    required this.iconSize,
    required this.shape,
    required this.showLabel,
  });

  @override
  Widget build(BuildContext context) {
    final contents = folder?.contents ?? const [];
    final preview = contents.take(4).toList();
    final padding = iconSize * 0.12;
    final innerSize = iconSize - padding * 2;
    final miniSize = (innerSize - 2) / 2;
    final label = folder?.title ?? '';
    final fontSize = (iconSize * 0.3).clamp(7.5, 10.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: iconSize,
          height: iconSize,
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(iconSize * 0.28),
          ),
          child: preview.isEmpty
              ? Icon(
                  Icons.folder,
                  color: Colors.white.withValues(alpha: 0.85),
                  size: innerSize * 0.8,
                )
              : Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    for (final item in preview)
                      SizedBox(
                        width: miniSize,
                        height: miniSize,
                        child: ShapedIcon(
                          iconBytes: item.icon,
                          shape: shape,
                          size: miniSize,
                        ),
                      ),
                  ],
                ),
        ),
        if (showLabel && label.isNotEmpty) ...[
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                height: 1.1,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _WidgetTile extends StatelessWidget {
  final Uint8List? previewImage;
  final bool isStack;

  const _WidgetTile({required this.previewImage, this.isStack = false});

  @override
  Widget build(BuildContext context) {
    final container = Container(
      margin: const EdgeInsets.all(2),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: previewImage != null
          ? Image.memory(
              previewImage!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            )
          : Center(
              child: Icon(
                isStack
                    ? Icons.dashboard_customize_outlined
                    : Icons.widgets_outlined,
                color: Colors.white.withValues(alpha: 0.85),
                size: 18,
              ),
            ),
    );
    return container;
  }
}

// ─── Bottom action item (icon + text label) ──────────────────────────────────

class _BottomBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BottomBarItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
