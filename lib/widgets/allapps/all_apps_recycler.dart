import 'package:flutter/material.dart';
import '../../models/app_info.dart';
import '../../models/item_info.dart';
import '../../models/launcher_settings.dart';
import '../../models/workspace_item_info.dart';
import '../../services/drag/drag_controller.dart';
import '../../utils/drawer_perf.dart';
import '../drag/pickup_feedback.dart';
import '../icons/badge_listener.dart';
import '../icons/bubble_text_view.dart';
import '../workspace/cell_layout.dart' show kDrawerSourcePage;
import 'all_apps_grid_adapter.dart';

class AllAppsRecycler extends StatefulWidget {
  final List<AppInfo> apps;
  final LauncherSettings settings;
  final DragController dragController;
  final void Function(AppInfo app) onAppTap;
  final void Function(AppInfo app, Offset globalPos) onAppLongPress;
  final VoidCallback onDragStarted;
  final void Function(bool wasAccepted) onDragEnded;
  final ScrollController? scrollController;

  const AllAppsRecycler({
    super.key,
    required this.apps,
    required this.settings,
    required this.dragController,
    required this.onAppTap,
    required this.onAppLongPress,
    required this.onDragStarted,
    required this.onDragEnded,
    this.scrollController,
  });

  @override
  State<AllAppsRecycler> createState() => _AllAppsRecyclerState();
}

class _AllAppsRecyclerState extends State<AllAppsRecycler> {
  List<DrawerItem>? _itemsCache;
  List<AppInfo>? _itemsCacheApps;
  int? _itemsCacheColumns;

  List<DrawerItem> _items() {
    final apps = widget.apps;
    final columns = widget.settings.drawerColumns;
    if (identical(apps, _itemsCacheApps) &&
        columns == _itemsCacheColumns &&
        _itemsCache != null) {
      return _itemsCache!;
    }
    final next = buildSections(apps, columns);
    _itemsCache = next;
    _itemsCacheApps = apps;
    _itemsCacheColumns = columns;
    return next;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    final columns = widget.settings.drawerColumns;

    return Scrollbar(
      controller: widget.scrollController,
      thumbVisibility: widget.settings.drawerShowScrollbar,
      child: PerfProbe(
        label: 'recycler.scrollView',
        measureLayout: true,
        measurePaint: true,
        child: CustomScrollView(
          controller: widget.scrollController,
          cacheExtent: 1400,
          slivers: [
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = items[index];
                  if (item is SectionHeader) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 0, 4),
                      child: Text(
                        item.letter,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }
                  if (item is AppRow) {
                    return RepaintBoundary(
                      child: PerfProbe(
                        label: 'recycler.row',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          child: Row(
                            children: [
                              for (final app in item.apps)
                                Expanded(
                                  child: Center(
                                    child: _DrawerAppIcon(
                                      key: ValueKey(app.packageName),
                                      app: app,
                                      settings: widget.settings,
                                      dragController: widget.dragController,
                                      onTap: () => widget.onAppTap(app),
                                      onLongPress: (pos) =>
                                          widget.onAppLongPress(app, pos),
                                      onDragStarted: widget.onDragStarted,
                                      onDragEnded: widget.onDragEnded,
                                    ),
                                  ),
                                ),
                              for (int i = 0;
                                  i < columns - item.apps.length;
                                  i++)
                                const Expanded(child: SizedBox.shrink()),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
                childCount: items.length,
                addRepaintBoundaries: false,
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
      ),
    );
  }
}

class _DrawerAppIcon extends StatefulWidget {
  final AppInfo app;
  final LauncherSettings settings;
  final DragController dragController;
  final VoidCallback onTap;
  final void Function(Offset globalPos) onLongPress;
  final VoidCallback onDragStarted;
  final void Function(bool wasAccepted) onDragEnded;

  const _DrawerAppIcon({
    super.key,
    required this.app,
    required this.settings,
    required this.dragController,
    required this.onTap,
    required this.onLongPress,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  @override
  State<_DrawerAppIcon> createState() => _DrawerAppIconState();
}

class _DrawerAppIconState extends State<_DrawerAppIcon> {
  bool _dragging = false;
  bool _dragArmed = false;
  bool _dragMoved = false;
  // Global position where the long-press armed; used to measure drag distance.
  Offset _dragStartGlobalPos = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final item = WorkspaceItemInfo(
      id: widget.app.id,
      itemType: ItemType.application,
      packageName: widget.app.packageName,
      componentName: widget.app.appComponentName,
      title: widget.app.name,
      icon: widget.app.icon,
      iconPath: widget.app.iconPath,
      launcherFeatureId: widget.app.launcherFeatureId,
    );
    final payload = DragPayload(
      item: item,
      sourcePage: kDrawerSourcePage,
      sourceSlot: -1,
    );

    final iconView = BadgeListener(
      packageName: widget.app.packageName,
      builder: (_, badge) => BubbleTextView(
        app: widget.app,
        iconSize: widget.settings.drawerIconSize,
        showLabel: widget.settings.showDrawerLabels,
        iconShape: widget.settings.iconShape,
        badgeCount: badge,
      ),
    );

    return LongPressDraggable<DragPayload>(
      data: payload,
      delay: const Duration(milliseconds: 350),
      onDragStarted: () {
        // Fires at long-press threshold — show the context menu here.
        // Do NOT navigate yet; wait until the user drags far enough.
        _dragArmed = true;
        _dragMoved = false;
        widget.dragController
            .startDrag(item, kDrawerSourcePage, -1, Offset.zero);
        if (mounted) setState(() => _dragging = true);
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && mounted) {
          final center = box.localToGlobal(
            Offset(box.size.width / 2, box.size.height / 2),
          );
          _dragStartGlobalPos = center;
          final iconBottom = box.localToGlobal(
            Offset(box.size.width / 2, box.size.height),
          );
          widget.onLongPress(iconBottom);
        }
      },
      onDragUpdate: (details) {
        widget.dragController.updateDragPosition(details.globalPosition);
        // Only navigate to home after a significant downward drag (~one grid row).
        if (_dragArmed && !_dragMoved) {
          final dy = details.globalPosition.dy - _dragStartGlobalPos.dy;
          if (dy > 80.0) {
            _dragMoved = true;
            widget.onDragStarted();
          }
        }
      },
      onDragEnd: (details) {
        final hadMoved = _dragMoved;
        _dragArmed = false;
        _dragMoved = false;
        _dragStartGlobalPos = Offset.zero;
        widget.dragController.cancelDrag();
        if (mounted) setState(() => _dragging = false);
        // Only notify if the user actually dragged to home; a plain long-press
        // release (no significant movement) must not dismiss the context menu.
        if (hadMoved) widget.onDragEnded(details.wasAccepted);
      },
      onDraggableCanceled: (_, __) {
        final hadMoved = _dragMoved;
        _dragArmed = false;
        _dragMoved = false;
        _dragStartGlobalPos = Offset.zero;
        widget.dragController.cancelDrag();
        if (mounted) setState(() => _dragging = false);
        // Only notify the container if the user had actually started dragging
        // (i.e. the drawer was already hidden). If the user just held and released
        // without moving, the context menu is still visible and we leave it alone.
        if (hadMoved) widget.onDragEnded(false);
      },
      feedback: PickupFeedback(
        child: BubbleTextView(
          app: widget.app,
          iconSize: widget.settings.drawerIconSize,
          showLabel: false,
          iconShape: widget.settings.iconShape,
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: iconView),
      child: GestureDetector(
        onTap: _dragging ? null : widget.onTap,
        // onLongPress removed: LongPressDraggable.onDragStarted handles it.
        child: iconView,
      ),
    );
  }
}
