import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../models/launcher_settings.dart';
import '../../services/drag/drag_controller.dart';
import '../../state/apps_cubit.dart';
import '../../state/search_cubit.dart';
import 'all_apps_recycler.dart';
import 'all_apps_search_bar.dart';

class AllAppsContainer extends StatefulWidget {
  final LauncherSettings settings;
  final DragController dragController;
  final void Function(AppInfo app) onAppTap;
  final void Function(AppInfo app) onAppLongPress;
  final VoidCallback onDismiss;

  const AllAppsContainer({
    super.key,
    required this.settings,
    required this.dragController,
    required this.onAppTap,
    required this.onAppLongPress,
    required this.onDismiss,
  });

  @override
  State<AllAppsContainer> createState() => _AllAppsContainerState();
}

class _AllAppsContainerState extends State<AllAppsContainer>
    with SingleTickerProviderStateMixin {
  ScrollController? _scrollController;
  late AnimationController _animController;
  late Animation<Offset> _slideAnim;

  double _dragStartY = 0;
  double _dragDy = 0;
  bool _isDismissing = false;
  bool _drawerDragging = false;

  @override
  void initState() {
    super.initState();
    if (widget.settings.drawerRememberScroll) {
      _scrollController = ScrollController();
    }
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
  }

  @override
  void dispose() {
    _scrollController?.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_isDismissing) return;
    _isDismissing = true;
    _animController.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  void _onVerticalDragStart(DragStartDetails d) {
    _dragStartY = d.globalPosition.dy;
    _dragDy = 0;
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    final dy = d.globalPosition.dy - _dragStartY;
    if (dy > 0) {
      setState(() => _dragDy = dy);
    }
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    final screenH = MediaQuery.of(context).size.height;
    if (velocity > 600 || _dragDy > screenH * 0.35) {
      _dismiss();
    } else {
      setState(() => _dragDy = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final dismissProgress = (_dragDy / screenH).clamp(0.0, 1.0);

    // When a drawer drag-to-home is in progress: keep widget alive but
    // invisible and non-absorbing so workspace DragTargets can receive the drop.
    if (_drawerDragging) {
      return AbsorbPointer(
        absorbing: false,
        child: Opacity(opacity: 0.0, child: const SizedBox.expand()),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: GestureDetector(
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: SlideTransition(
          position: _slideAnim,
          child: Transform.translate(
            offset: Offset(0, _dragDy),
            child: Opacity(
              opacity: (1.0 - dismissProgress * 0.5).clamp(0.0, 1.0),
              child: Material(
                color: Colors.transparent,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: Container(
                    height: screenH,
                    color: Colors.black.withValues(alpha: 0.60),
                    child: Column(
                      children: [
                        SizedBox(height: MediaQuery.of(context).padding.top + 16),
                        _SearchRow(onDismiss: _dismiss),
                        const SizedBox(height: 4),
                        Expanded(child: _buildBody()),
                        SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
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
  }

  Widget _buildBody() {
    return BlocBuilder<SearchCubit, SearchState>(
      builder: (context, searchState) {
        final appsState = context.watch<AppsCubit>().state;
        final displayApps = searchState.query.isEmpty
            ? appsState.apps.where((a) => !a.isHidden).toList()
            : context.read<AppsCubit>().searchApps(searchState.query);

        return AllAppsRecycler(
          apps: displayApps,
          settings: widget.settings,
          badgeCounts: appsState.badgeCounts,
          dragController: widget.dragController,
          onAppTap: widget.onAppTap,
          onAppLongPress: widget.onAppLongPress,
          scrollController: _scrollController,
          onDragStarted: () => setState(() => _drawerDragging = true),
          onDragEnded: (wasAccepted) {
            setState(() => _drawerDragging = false);
            if (wasAccepted) _dismiss();
          },
        );
      },
    );
  }
}

class _SearchRow extends StatelessWidget {
  final VoidCallback onDismiss;
  const _SearchRow({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Expanded(child: AllAppsSearchBar()),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDismiss,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}
