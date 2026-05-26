import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../models/folder_info.dart';
import '../../models/launcher_settings.dart';
import '../../models/workspace_item_info.dart';
import '../../state/apps_cubit.dart';
import '../../state/workspace_cubit.dart';
import '../icons/shaped_icon.dart';
import 'threshold_reorderable_list.dart';

class EditModeOverlay extends StatefulWidget {
  final LauncherSettings settings;
  final VoidCallback onDismiss;
  final VoidCallback onWallpaper;
  final VoidCallback onThemes;
  final VoidCallback onWidgets;
  final VoidCallback onSettings;
  final ValueChanged<int> onPageSelected;

  const EditModeOverlay({
    super.key,
    required this.settings,
    required this.onDismiss,
    required this.onWallpaper,
    required this.onThemes,
    required this.onWidgets,
    required this.onSettings,
    required this.onPageSelected,
  });

  @override
  State<EditModeOverlay> createState() => _EditModeOverlayState();
}

class _EditModeOverlayState extends State<EditModeOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late ScrollController _scrollController;
  int _displayedPage = 0;
  bool _didAlignInitialPage = false;
  double _itemExtent = 1;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    _displayedPage = context.read<WorkspaceCubit>().state.currentPage;
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _itemExtent <= 1) return;
    final raw = _scrollController.position.pixels / _itemExtent;
    final pageCount = context.read<WorkspaceCubit>().state.pages.length;
    final nearest = raw.round();
    // Clamp to real pages (the add-page slot at index pageCount has no dot).
    final clamped = nearest.clamp(0, pageCount - 1);
    final mapped = nearest >= pageCount ? -1 : clamped;
    if (mapped != _displayedPage) {
      setState(() => _displayedPage = mapped);
    }
  }

  void _jumpToPage(int pageIndex) {
    if (!_scrollController.hasClients || _itemExtent <= 1) return;
    final target = (pageIndex * _itemExtent)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _animController.dispose();
    super.dispose();
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
    setState(() => _displayedPage = cubit.state.pages.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
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
    final target = _displayedPage.clamp(0, (newLength - 1).clamp(0, newLength));
    setState(() => _displayedPage = target);
  }

  void _onReorder(int oldIndex, int newIndex) {
    final pageCount = context.read<WorkspaceCubit>().state.pages.length;
    // The trailing slot at `pageCount` is the add-page card; it isn't movable
    // and can't be a drop destination past the last real page.
    if (oldIndex >= pageCount) return;
    if (newIndex > pageCount) newIndex = pageCount;
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    final cubit = context.read<WorkspaceCubit>();
    cubit.movePage(oldIndex, newIndex);
    setState(() => _displayedPage = newIndex);
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
              // _displayedPage == -1 means the add-page card is centered;
              // no dot should be active in that case.
              final activeIndex = _displayedPage < 0
                  ? -1
                  : _displayedPage.clamp(0, state.pages.length - 1);
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
                    onDotTap: _jumpToPage,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final appsByPackage =
            context.select((AppsCubit cubit) => cubit.state.appsByPackage);
        // Show ~2 thumbnails per screen so dragging between slots feels natural.
        final viewH = constraints.maxHeight - 8; // vertical padding allowance
        final thumbH = viewH;
        final thumbW = thumbH * 9 / 16;
        final horizontalInset =
            ((constraints.maxWidth - thumbW) / 2).clamp(12.0, 80.0);
        _itemExtent = thumbW + 12;
        _alignInitialPage(itemExtent: _itemExtent);

        return ThresholdReorderableList(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding:
              EdgeInsets.symmetric(horizontal: horizontalInset, vertical: 4),
          // +1 for the trailing add-page card (not part of the cubit state).
          itemCount: state.pages.length + 1,
          onReorder: _onReorder,
          // Slow the edge auto-scroll way down so neighbors don't whip past
          // when the dragged page gets near the left/right edge. Stock value
          // is ~50; 8 makes it a calm crawl.
          autoScrollerVelocityScalar: 8,
          proxyDecorator: (child, index, animation) {
            // Lifted card shrinks to 85% of the original so it reads as a
            // distinct "picked-up" object rather than a full-size ghost.
            return AnimatedBuilder(
              animation: animation,
              builder: (context, c) {
                final t = Curves.easeOut.transform(animation.value);
                final scale = 1.0 - 0.15 * t; // 1.0 → 0.85
                return Transform.scale(
                  scale: scale,
                  child: Material(
                    color: Colors.transparent,
                    elevation: 14 * t,
                    shadowColor: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(22),
                    child: Opacity(opacity: 0.92, child: c),
                  ),
                );
              },
              child: child,
            );
          },
          itemBuilder: (context, i) {
            // Last slot is the static "+" card. Not reorderable, not deletable.
            if (i == state.pages.length) {
              return Padding(
                key: const ValueKey('edit-mode-add-page-card'),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: SizedBox(
                  width: thumbW,
                  child: IgnorePointer(
                    ignoring: false,
                    child: _AddPageCard(onTap: _addPage),
                  ),
                ),
              );
            }
            final page = state.pages[i];
            return Padding(
              key: ObjectKey(page),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox(
                width: thumbW,
                child: _LongPressReorderListener(
                  index: i,
                  // Deliberate ~700ms long-press to pick up — longer than the
                  // stock 500ms delayed listener so casual taps/scrolls don't
                  // grab a page. Once lifted, neighbors shift one-at-a-time
                  // as you cross each one's midpoint. Release to drop.
                  child: _PageCard(
                    page: page,
                    folders: state.folders,
                    settings: widget.settings,
                    appsByPackage: appsByPackage,
                    onJump: () {
                      widget.onPageSelected(i);
                      _dismiss();
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _alignInitialPage({required double itemExtent}) {
    if (_didAlignInitialPage) return;
    _didAlignInitialPage = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = (_displayedPage * itemExtent)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(target);
    });
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
            color:
                enabled ? Colors.white : Colors.white.withValues(alpha: 0.35),
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
  final ValueChanged<int> onDotTap;

  const _PageDots({
    required this.count,
    required this.active,
    required this.onAddPage,
    required this.onDotTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            onTap: () => onDotTap(i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              // Bigger hit area than the visible dot so it's easy to tap.
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
          ),
        const SizedBox(width: 4),
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
  final WorkspacePage page;
  final Map<String, FolderInfo> folders;
  final Map<String, AppInfo> appsByPackage;
  final LauncherSettings settings;
  final VoidCallback onJump;

  const _PageCard({
    required this.page,
    required this.folders,
    required this.appsByPackage,
    required this.settings,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('edit-mode-page-card'),
      onTap: onJump,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.55),
            width: 1.4,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.all(6),
        child: IgnorePointer(
          child: _PagePreview(
            page: page,
            folders: folders,
            appsByPackage: appsByPackage,
            settings: settings,
          ),
        ),
      ),
    );
  }
}

class _AddPageCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddPageCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        child: Center(
          child: Icon(
            Icons.add,
            color: Colors.white.withValues(alpha: 0.85),
            size: 48,
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
  final Map<String, AppInfo> appsByPackage;
  final LauncherSettings settings;

  const _PagePreview({
    required this.page,
    required this.folders,
    required this.appsByPackage,
    required this.settings,
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
          liveApp: appsByPackage[item.packageName],
          iconSize: iconSize,
          shape: settings.iconShape,
          showLabel: settings.showLabels,
        );
      case FolderSlot(:final folderId):
        final folder = folders[folderId];
        return _FolderTile(
          folder: folder,
          appsByPackage: appsByPackage,
          iconSize: iconSize,
          shape: settings.iconShape,
          showLabel: settings.showLabels,
        );
      case WidgetSlot(:final widget):
        return _WidgetTile(appWidgetId: widget.appWidgetId);
      case WidgetStackSlot(:final widgets):
        final firstId = widgets
            .map((w) => w.appWidgetId)
            .firstWhere((id) => id > 0, orElse: () => -1);
        return _WidgetTile(
          appWidgetId: firstId > 0 ? firstId : null,
          isStack: true,
        );
      case EmptySlot():
        return const SizedBox.shrink();
    }
  }
}

class _AppTile extends StatelessWidget {
  final WorkspaceItemInfo item;
  final AppInfo? liveApp;
  final double iconSize;
  final String shape;
  final bool showLabel;

  const _AppTile({
    required this.item,
    required this.liveApp,
    required this.iconSize,
    required this.shape,
    required this.showLabel,
  });

  @override
  Widget build(BuildContext context) {
    final label = item.title ?? liveApp?.name ?? '';
    final fontSize = (iconSize * 0.3).clamp(7.5, 10.0);
    final cacheKey = item.packageName.isEmpty ? null : item.packageName;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        ShapedIcon(
          iconBytes: liveApp?.icon ?? item.icon,
          iconPath: liveApp?.iconPath ?? item.iconPath,
          cacheKey: cacheKey,
          shape: shape,
          size: iconSize,
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

class _FolderTile extends StatelessWidget {
  final FolderInfo? folder;
  final Map<String, AppInfo> appsByPackage;
  final double iconSize;
  final String shape;
  final bool showLabel;

  const _FolderTile({
    required this.folder,
    required this.appsByPackage,
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
                        child: _FolderPreviewIcon(
                          item: item,
                          liveApp: appsByPackage[item.packageName],
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

class _FolderPreviewIcon extends StatelessWidget {
  final WorkspaceItemInfo item;
  final AppInfo? liveApp;
  final String shape;
  final double size;

  const _FolderPreviewIcon({
    required this.item,
    required this.liveApp,
    required this.shape,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final cacheKey = item.packageName.isEmpty ? null : item.packageName;
    return ShapedIcon(
      iconBytes: liveApp?.icon ?? item.icon,
      iconPath: liveApp?.iconPath ?? item.iconPath,
      cacheKey: cacheKey,
      shape: shape,
      size: size,
    );
  }
}

class _WidgetTile extends StatelessWidget {
  final int? appWidgetId;
  final bool isStack;

  const _WidgetTile({required this.appWidgetId, this.isStack = false});

  @override
  Widget build(BuildContext context) {
    final id = appWidgetId;
    return Container(
      margin: const EdgeInsets.all(2),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: id != null && id > 0
          ? AndroidView(
              key: ValueKey('edit-overlay-$id'),
              viewType: 'com.genrevibes.smartlauncher/widget_host_view',
              creationParams: {'appWidgetId': id},
              creationParamsCodec: const StandardMessageCodec(),
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

/// A drag-start listener for ReorderableListView that requires a deliberate
/// long-press before pickup. Stock [ReorderableDelayedDragStartListener] uses
/// the 500ms [kLongPressTimeout]; this one uses 700ms so casual taps and
/// scrolls won't accidentally grab a page.
class _LongPressReorderListener extends ThresholdReorderableDragStartListener {
  const _LongPressReorderListener({
    required super.child,
    required super.index,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return DelayedMultiDragGestureRecognizer(
      delay: const Duration(milliseconds: 700),
      debugOwner: this,
    );
  }
}
