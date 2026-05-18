import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../models/launcher_settings.dart';
import '../../services/drag/drag_controller.dart';
import '../../services/launcher_service.dart';
import '../../state/apps_cubit.dart';
import '../../state/search_cubit.dart';
import 'all_apps_recycler.dart';
import 'all_apps_search_bar.dart';

class AllAppsContainer extends StatefulWidget {
  final LauncherSettings settings;
  final DragController dragController;
  final void Function(AppInfo app) onAppTap;
  final void Function(AppInfo app) onAddToHome;
  final VoidCallback onDismiss;
  final VoidCallback? onDragToHome;
  /// Called when the user started a drag-to-home but cancelled it (did not drop
  /// on a valid target). Lets the home screen reset its workspace visibility.
  final VoidCallback? onDragCancelled;

  const AllAppsContainer({
    super.key,
    required this.settings,
    required this.dragController,
    required this.onAppTap,
    required this.onAddToHome,
    required this.onDismiss,
    this.onDragToHome,
    this.onDragCancelled,
  });

  @override
  State<AllAppsContainer> createState() => _AllAppsContainerState();
}

class _AllAppsContainerState extends State<AllAppsContainer>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _animController;
  late Animation<Offset> _slideAnim;

  double _dragStartY = 0;
  double _dragDy = 0;
  bool _isDismissing = false;
  bool _drawerDragging = false;

  AppInfo? _menuApp;
  Offset _menuPos = Offset.zero;

  @override
  void initState() {
    super.initState();
    // Always create a scroll controller to prevent PrimaryScrollController conflicts.
    _scrollController = ScrollController();
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
    _scrollController.dispose();
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

  void _showMenu(AppInfo app, Offset globalPos) {
    setState(() {
      _menuApp = app;
      _menuPos = globalPos;
    });
  }

  void _dismissMenu() => setState(() => _menuApp = null);

  void _onVerticalDragStart(DragStartDetails d) {
    if (_menuApp != null) _dismissMenu();
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
    final screenW = MediaQuery.of(context).size.width;
    final dismissProgress = (_dragDy / screenH).clamp(0.0, 1.0);

    // When the user is dragging to home, keep the widget tree alive so that
    // LongPressDraggable can continue receiving pointer events. We hide it
    // visually with Opacity and block new input with IgnorePointer.
    return IgnorePointer(
      ignoring: _drawerDragging,
      child: Opacity(
        opacity: _drawerDragging ? 0.0 : 1.0,
        child: _buildContent(screenH, screenW, dismissProgress),
      ),
    );
  }

  Widget _buildContent(double screenH, double screenW, double dismissProgress) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: GestureDetector(
        onVerticalDragStart: _drawerDragging ? null : _onVerticalDragStart,
        onVerticalDragUpdate: _drawerDragging ? null : _onVerticalDragUpdate,
        onVerticalDragEnd: _drawerDragging ? null : _onVerticalDragEnd,
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
                  child: Stack(
                    children: [
                      Container(
                        height: screenH,
                        color: widget.settings.drawerShowBackground
                            ? widget.settings.drawerBackgroundColor
                                .withValues(alpha: widget.settings.drawerBackgroundOpacity)
                            : Colors.transparent,
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
                      if (_menuApp != null) ...[
                        // Tap-outside or swipe dismisses the menu
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: _dismissMenu,
                            onVerticalDragStart: (_) => _dismissMenu(),
                            onHorizontalDragStart: (_) => _dismissMenu(),
                            behavior: HitTestBehavior.translucent,
                            child: const SizedBox.expand(),
                          ),
                        ),
                        // Context menu card positioned near the icon
                        _buildMenuCard(screenW, screenH),
                      ],
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

  Widget _buildMenuCard(double screenW, double screenH) {
    const menuW = 188.0;
    const menuH = 128.0;
    const gap = 10.0;
    final x = (_menuPos.dx - menuW / 2).clamp(8.0, screenW - menuW - 8);
    // _menuPos.dy is the bottom edge of the icon; prefer showing below
    final belowY = _menuPos.dy + gap;
    final approxIconH = widget.settings.drawerIconSize +
        (widget.settings.showDrawerLabels ? 20.0 : 0.0) +
        8.0;
    final aboveY = _menuPos.dy - approxIconH - menuH - gap;
    final rawY = (belowY + menuH <= screenH - gap) ? belowY : aboveY;
    final y = rawY.clamp(8.0, screenH - menuH - 8);

    return Positioned(
      left: x,
      top: y,
      child: _AppContextMenu(
        app: _menuApp!,
        onAddToHome: () {
          final app = _menuApp!;
          _dismissMenu();
          _dismiss();
          widget.onAddToHome(app);
        },
        onAppInfo: () {
          final pkg = _menuApp!.packageName;
          _dismissMenu();
          LauncherService.openAppSettings(pkg);
        },
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
          dragController: widget.dragController,
          onAppTap: widget.onAppTap,
          onAppLongPress: _showMenu,
          scrollController: _scrollController,
          onDragStarted: () {
            // Fires on first finger movement — safe to dismiss menu and reveal home.
            _dismissMenu();
            setState(() => _drawerDragging = true);
            widget.onDragToHome?.call();
          },
          onDragEnded: (wasAccepted) {
            _dismissMenu();
            setState(() => _drawerDragging = false);
            if (wasAccepted) {
              // Drawer was already invisible during the drag (opacity 0).
              // Skip the slide-out animation — just close instantly so the
              // user never sees the drawer animate back in after the drop.
              widget.onDismiss();
            } else {
              widget.onDragCancelled?.call();
            }
          },
        );
      },
    );
  }
}

// ─── Context menu ─────────────────────────────────────────────────────────────

class _AppContextMenu extends StatelessWidget {
  final AppInfo app;
  final VoidCallback onAddToHome;
  final VoidCallback onAppInfo;

  const _AppContextMenu({
    required this.app,
    required this.onAddToHome,
    required this.onAppInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 188,
        decoration: BoxDecoration(
          color: Colors.grey[850]!.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
              child: Text(
                app.name,
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(color: Colors.white12, height: 1, thickness: 1),
            _ContextMenuItem(icon: Icons.add_to_home_screen, label: 'Add to Home', onTap: onAddToHome),
            _ContextMenuItem(icon: Icons.info_outline, label: 'App Info', onTap: onAppInfo),
          ],
        ),
      ),
    );
  }
}

class _ContextMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ContextMenuItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 18),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ─── Search row ───────────────────────────────────────────────────────────────

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
