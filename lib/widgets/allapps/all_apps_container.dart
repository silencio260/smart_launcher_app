import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../models/launcher_feature.dart';
import '../../models/launcher_settings.dart';
import '../../services/feature_launch_dispatcher.dart';
import '../../services/drag/drag_controller.dart';
import '../../services/launcher_service.dart';
import '../../state/apps_cubit.dart';
import '../../state/search_cubit.dart';
import '../../state/settings_cubit.dart';
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
    ).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
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
    // LongPressDraggable can continue receiving pointer events. Visibility
    // with maintainState avoids the saveLayer cost an Opacity(0) wrapper
    // would impose while still hiding the drawer visually.
    return Visibility(
      visible: !_drawerDragging,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      maintainInteractivity: false,
      child: _buildContent(screenH, screenW, dismissProgress),
    );
  }

  Widget _buildContent(double screenH, double screenW, double dismissProgress) {
    // Keep the steady-state drawer path free of BackdropFilter. Full-screen
    // blur was the most expensive part of first-open + initial scroll.
    // Opacity-based fade only matters while the user is dragging to dismiss.
    // Skipping the Opacity wrapper otherwise removes a saveLayer from the
    // steady-state scroll path.
    final fade = (1.0 - dismissProgress * 0.5).clamp(0.0, 1.0);
    final isDragging = dismissProgress > 0;

    Widget content = Material(
      color: Colors.transparent,
      child: _buildStack(screenH, screenW),
    );
    if (isDragging) {
      content = Opacity(opacity: fade, child: content);
    }

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
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _buildStack(double screenH, double screenW) {
    return Stack(
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
          Positioned.fill(
            child: GestureDetector(
              onTap: _dismissMenu,
              onVerticalDragStart: (_) => _dismissMenu(),
              onHorizontalDragStart: (_) => _dismissMenu(),
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),
          ),
          _buildMenuCard(screenW, screenH),
        ],
      ],
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
          final app = _menuApp!;
          _dismissMenu();
          final featureId = LauncherFeatureCatalog.idForApp(app);
          if (featureId != null) {
            FeatureLaunchDispatcher.openFeature(context, featureId);
          } else {
            LauncherService.openAppSettings(app.packageName);
          }
        },
        onHideIcon: () {
          final app = _menuApp!;
          _dismissMenu();
          final hidden = widget.settings.hiddenApps.toSet()
            ..add(app.launcherKey);
          context.read<SettingsCubit>().update(
                widget.settings.copyWith(hiddenApps: hidden.toList()..sort()),
              );
        },
      ),
    );
  }

  Widget _buildBody() {
    return BlocBuilder<SearchCubit, SearchState>(
      buildWhen: (prev, next) => prev.query != next.query,
      builder: (context, searchState) {
        return BlocBuilder<AppsCubit, AppsState>(
          // Avoid rebuilding the grid for every BadgeStore tick or loading
          // flag change — only the visible app list matters here.
          buildWhen: (prev, next) => !identical(prev.apps, next.apps),
          builder: (context, appsState) {
            final hidden = widget.settings.hiddenApps.toSet();
            final displayApps = searchState.query.isEmpty
                ? _visibleApps(appsState.apps, hidden)
                : context
                    .read<AppsCubit>()
                    .searchApps(searchState.query)
                    .where((a) =>
                        !hidden.contains(a.launcherKey) &&
                        !hidden.contains(a.packageName))
                    .toList(growable: false);
            return _buildRecycler(displayApps);
          },
        );
      },
    );
  }

  List<AppInfo>? _visibleCache;
  List<AppInfo>? _visibleCacheSource;
  Set<String>? _visibleCacheHidden;

  List<AppInfo> _visibleApps(List<AppInfo> source, Set<String> hidden) {
    if (identical(source, _visibleCacheSource) &&
        _visibleCache != null &&
        _visibleCacheHidden != null &&
        _setsEqual(_visibleCacheHidden!, hidden)) {
      return _visibleCache!;
    }
    final result = hidden.isEmpty
        ? source
        : source
            .where((a) =>
                !hidden.contains(a.launcherKey) &&
                !hidden.contains(a.packageName))
            .toList(growable: false);
    _visibleCacheSource = source;
    _visibleCache = result;
    _visibleCacheHidden = hidden;
    return result;
  }

  static bool _setsEqual(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }

  Widget _buildRecycler(List<AppInfo> displayApps) {
    return AllAppsRecycler(
      apps: displayApps,
      settings: widget.settings,
      dragController: widget.dragController,
      onAppTap: widget.onAppTap,
      onAppLongPress: _showMenu,
      scrollController: _scrollController,
      onDragStarted: () {
        _dismissMenu();
        setState(() => _drawerDragging = true);
        widget.onDragToHome?.call();
      },
      onDragEnded: (wasAccepted) {
        _dismissMenu();
        setState(() => _drawerDragging = false);
        if (wasAccepted) {
          widget.onDismiss();
        } else {
          widget.onDragCancelled?.call();
        }
      },
    );
  }
}

// ─── Context menu ─────────────────────────────────────────────────────────────

class _AppContextMenu extends StatelessWidget {
  final AppInfo app;
  final VoidCallback onAddToHome;
  final VoidCallback onAppInfo;
  final VoidCallback onHideIcon;

  const _AppContextMenu({
    required this.app,
    required this.onAddToHome,
    required this.onAppInfo,
    required this.onHideIcon,
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
          boxShadow: const [
            BoxShadow(
                color: Colors.black54, blurRadius: 14, offset: Offset(0, 4))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
              child: Text(
                app.name,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(color: Colors.white12, height: 1, thickness: 1),
            _ContextMenuItem(
                icon: Icons.add_to_home_screen,
                label: 'Add to Home',
                onTap: onAddToHome),
            if (app.isInternalFeature)
              _ContextMenuItem(
                  icon: Icons.visibility_off_outlined,
                  label: 'Hide Icon',
                  onTap: onHideIcon)
            else
              _ContextMenuItem(
                  icon: Icons.info_outline,
                  label: 'App Info',
                  onTap: onAppInfo),
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

  const _ContextMenuItem(
      {required this.icon, required this.label, required this.onTap});

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
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
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
              child: const Icon(Icons.keyboard_arrow_down,
                  color: Colors.white70, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}
