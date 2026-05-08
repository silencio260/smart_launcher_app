import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/launcher_settings.dart';
import '../../state/workspace_cubit.dart';

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
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

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
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _dismiss() {
    _animController.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: GestureDetector(
        onTap: _dismiss,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            color: Colors.black.withValues(alpha: 0.65),
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  const Text(
                    'Edit Home Screen',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(child: _buildPageArea()),
                  const SizedBox(height: 8),
                  _buildBottomBar(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageArea() {
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, state) {
        return Column(
          children: [
            // Trash drop zone
            DragTarget<int>(
              onWillAcceptWithDetails: (_) => state.pages.length > 1,
              onAcceptWithDetails: (details) =>
                  context.read<WorkspaceCubit>().removePage(details.data),
              builder: (_, candidateData, __) {
                final isHovered = candidateData.isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: isHovered ? 54 : 42,
                  margin: const EdgeInsets.symmetric(horizontal: 48),
                  decoration: BoxDecoration(
                    color: isHovered
                        ? Colors.red.withValues(alpha: 0.8)
                        : Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isHovered ? Icons.delete_forever : Icons.delete_outline,
                        color: Colors.white,
                        size: isHovered ? 22 : 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isHovered ? 'Release to delete' : 'Drag page here to delete',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            // Page thumbnails
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (int i = 0; i < state.pages.length; i++) ...[
                      _PageThumbnailCard(
                        pageIndex: i,
                        page: state.pages[i],
                        settings: widget.settings,
                        isCurrentPage: i == state.currentPage,
                        onTap: () {
                          context.read<WorkspaceCubit>().setCurrentPage(i);
                          _dismiss();
                        },
                      ),
                      const SizedBox(width: 12),
                    ],
                    // Add page button
                    GestureDetector(
                      onTap: () =>
                          context.read<WorkspaceCubit>().addPage(),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 90,
                        height: 130,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add, color: Colors.white, size: 28),
                            const SizedBox(height: 4),
                            Text(
                              'Add Page',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Page indicator dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(state.pages.length, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == state.currentPage ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == state.currentPage
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return GestureDetector(
      // Prevent taps on the bar from dismissing the overlay
      onTap: () {},
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _BottomBarItem(
              icon: Icons.wallpaper,
              label: 'Wallpaper',
              onTap: widget.onWallpaper,
            ),
            _BottomBarItem(
              icon: Icons.palette_outlined,
              label: 'Themes',
              onTap: () {},
            ),
            _BottomBarItem(
              icon: Icons.widgets_outlined,
              label: 'Widgets',
              onTap: () {},
            ),
            _BottomBarItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: widget.onSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _PageThumbnailCard extends StatelessWidget {
  final int pageIndex;
  final WorkspacePage page;
  final LauncherSettings settings;
  final bool isCurrentPage;
  final VoidCallback onTap;

  const _PageThumbnailCard({
    required this.pageIndex,
    required this.page,
    required this.settings,
    required this.isCurrentPage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rows = settings.gridRows;
    final cols = settings.gridColumns;
    final total = rows * cols;

    return LongPressDraggable<int>(
      data: pageIndex,
      delay: const Duration(milliseconds: 300),
      feedback: _buildCard(cols, total, isDragging: true),
      childWhenDragging:
          Opacity(opacity: 0.35, child: _buildCard(cols, total)),
      child: GestureDetector(
        onTap: onTap,
        child: _buildCard(cols, total),
      ),
    );
  }

  Widget _buildCard(int cols, int total, {bool isDragging = false}) {
    return Container(
      width: 90,
      height: 130,
      decoration: BoxDecoration(
        color: Colors.white
            .withValues(alpha: isDragging ? 0.28 : (isCurrentPage ? 0.2 : 0.12)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrentPage
              ? Colors.white
              : Colors.white.withValues(alpha: 0.3),
          width: isCurrentPage ? 2 : 1,
        ),
        boxShadow: isDragging
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: total,
              itemBuilder: (_, i) {
                final content = page.slots[i];
                final hasContent =
                    content != null && content is! EmptySlot;
                return Container(
                  decoration: BoxDecoration(
                    color: hasContent
                        ? Colors.white.withValues(alpha: 0.75)
                        : Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${pageIndex + 1}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

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
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
