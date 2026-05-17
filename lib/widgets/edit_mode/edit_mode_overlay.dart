import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/folder_info.dart';
import '../../models/launcher_settings.dart';
import '../../models/workspace_item_info.dart';
import '../../state/workspace_cubit.dart';
import '../icons/shaped_icon.dart';

class EditModeOverlay extends StatefulWidget {
  final LauncherSettings settings;
  final VoidCallback onDismiss;
  final VoidCallback onWallpaper;
  final VoidCallback onSettings;

  const EditModeOverlay({
    super.key,
    required this.settings,
    required this.onDismiss,
    required this.onWallpaper,
    required this.onSettings,
  });

  @override
  State<EditModeOverlay> createState() => _EditModeOverlayState();
}

class _EditModeOverlayState extends State<EditModeOverlay>
    with SingleTickerProviderStateMixin {
  static const double _viewportFraction = 0.78;

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

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: GestureDetector(
        onTap: _dismiss,
        behavior: HitTestBehavior.opaque,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.55),
            child: SafeArea(
              child: BlocBuilder<WorkspaceCubit, WorkspaceState>(
                builder: (context, state) {
                  return Column(
                    children: [
                      const SizedBox(height: 12),
                      _RemovePill(
                        enabled: state.pages.length > 1,
                        onAccept: (pageIndex) {
                          context.read<WorkspaceCubit>().removePage(pageIndex);
                        },
                      ),
                      const SizedBox(height: 16),
                      Expanded(child: _buildPagesRow(state)),
                      const SizedBox(height: 14),
                      _PageDots(
                        count: state.pages.length,
                        active: _displayedPage.clamp(0, state.pages.length - 1),
                      ),
                      const SizedBox(height: 14),
                      _buildBottomBar(),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
            ),
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
        itemCount: state.pages.length + 1,
        onPageChanged: (i) => setState(() => _displayedPage = i),
        itemBuilder: (context, i) {
          if (i == state.pages.length) {
            return _AddPageCard(
              onTap: () {
                final cubit = context.read<WorkspaceCubit>();
                cubit.addPage();
                _pageController.animateToPage(
                  cubit.state.pages.length - 1,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                );
              },
            );
          }
          return _PageCard(
            pageIndex: i,
            page: state.pages[i],
            folders: state.folders,
            settings: widget.settings,
            isCurrent: i == _displayedPage,
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
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(28),
        ),
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
              icon: Icons.palette_outlined,
              label: 'Themes',
              onTap: () {
                _commitCurrentPage();
                widget.onSettings();
              },
            ),
            _BottomBarItem(
              icon: Icons.widgets_outlined,
              label: 'Widgets',
              onTap: () {
                _commitCurrentPage();
                widget.onSettings();
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

// ─── Remove pill ─────────────────────────────────────────────────────────────

class _RemovePill extends StatelessWidget {
  final bool enabled;
  final ValueChanged<int> onAccept;

  const _RemovePill({required this.enabled, required this.onAccept});

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
          padding: EdgeInsets.symmetric(
            horizontal: hovering ? 26 : 22,
            vertical: hovering ? 14 : 12,
          ),
          decoration: BoxDecoration(
            color: hovering
                ? Colors.red.withValues(alpha: 0.85)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
              color: Colors.white.withValues(alpha: hovering ? 0.0 : 0.85),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hovering ? Icons.delete_forever : Icons.close,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Remove',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Page dots ───────────────────────────────────────────────────────────────

class _PageDots extends StatelessWidget {
  final int count;
  final int active;

  const _PageDots({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white
                : Colors.white.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

// ─── Page card (draggable + tappable, holds the preview) ─────────────────────

class _PageCard extends StatelessWidget {
  final int pageIndex;
  final WorkspacePage page;
  final Map<String, FolderInfo> folders;
  final LauncherSettings settings;
  final bool isCurrent;
  final VoidCallback onTap;

  const _PageCard({
    required this.pageIndex,
    required this.page,
    required this.folders,
    required this.settings,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = _buildCard(context);
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
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: card),
        child: GestureDetector(
          onTap: onTap,
          child: card,
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isCurrent ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isCurrent
              ? Colors.white.withValues(alpha: 0.95)
              : Colors.white.withValues(alpha: 0.25),
          width: isCurrent ? 1.6 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Expanded(
            child: _PagePreview(
              page: page,
              folders: folders,
              settings: settings,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${pageIndex + 1}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 11,
            ),
          ),
        ],
      ),
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
              color: Colors.white.withValues(alpha: 0.24),
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

// ─── Add-page card ───────────────────────────────────────────────────────────

class _AddPageCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddPageCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: DottedBorderCard(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 10),
              Text(
                'Add page',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DottedBorderCard extends StatelessWidget {
  final Widget child;

  const DottedBorderCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: child,
    );
  }
}

// ─── Real-content page preview (icons, folders, widget tiles) ────────────────

class _PagePreview extends StatelessWidget {
  final WorkspacePage page;
  final Map<String, FolderInfo> folders;
  final LauncherSettings settings;

  const _PagePreview({
    required this.page,
    required this.folders,
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
    final iconSize = (cellW * 0.62).clamp(14.0, 40.0);
    switch (content) {
      case AppSlot(:final item):
        return _AppTile(
          item: item,
          iconSize: iconSize,
          shape: settings.iconShape,
        );
      case FolderSlot(:final folderId):
        final folder = folders[folderId];
        return _FolderTile(
          folder: folder,
          iconSize: iconSize,
          shape: settings.iconShape,
        );
      case WidgetSlot():
        return const _WidgetTile(isStack: false);
      case WidgetStackSlot():
        return const _WidgetTile(isStack: true);
      case EmptySlot():
        return const SizedBox.shrink();
    }
  }
}

class _AppTile extends StatelessWidget {
  final WorkspaceItemInfo item;
  final double iconSize;
  final String shape;

  const _AppTile({
    required this.item,
    required this.iconSize,
    required this.shape,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ShapedIcon(
        iconBytes: item.icon,
        shape: shape,
        size: iconSize,
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  final FolderInfo? folder;
  final double iconSize;
  final String shape;

  const _FolderTile({
    required this.folder,
    required this.iconSize,
    required this.shape,
  });

  @override
  Widget build(BuildContext context) {
    final contents = folder?.contents ?? const [];
    final preview = contents.take(4).toList();
    final padding = iconSize * 0.12;
    final innerSize = iconSize - padding * 2;
    final miniSize = (innerSize - 2) / 2;

    return Center(
      child: Container(
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
    );
  }
}

class _WidgetTile extends StatelessWidget {
  final bool isStack;

  const _WidgetTile({required this.isStack});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Center(
        child: Icon(
          isStack ? Icons.dashboard_customize_outlined : Icons.widgets_outlined,
          color: Colors.white.withValues(alpha: 0.85),
          size: 18,
        ),
      ),
    );
  }
}

// ─── Bottom action bar item ──────────────────────────────────────────────────

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
