import 'package:flutter/material.dart';
import '../../models/app_info.dart';
import '../../models/item_info.dart';
import '../../models/launcher_settings.dart';
import '../../models/workspace_item_info.dart';
import '../../services/drag/drag_controller.dart';
import '../icons/bubble_text_view.dart';
import '../workspace/cell_layout.dart' show kDrawerSourcePage;
import 'all_apps_grid_adapter.dart';

class AllAppsRecycler extends StatelessWidget {
  final List<AppInfo> apps;
  final LauncherSettings settings;
  final Map<String, int> badgeCounts;
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
    required this.badgeCounts,
    required this.dragController,
    required this.onAppTap,
    required this.onAppLongPress,
    required this.onDragStarted,
    required this.onDragEnded,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final items = buildSections(apps, settings.drawerColumns);

    return Scrollbar(
      controller: scrollController,
      thumbVisibility: settings.drawerShowScrollbar,
      child: CustomScrollView(
        controller: scrollController,
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
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        ...item.apps.map((app) => Expanded(
                              child: Center(
                                child: _DrawerAppIcon(
                                  app: app,
                                  settings: settings,
                                  badgeCount: badgeCounts[app.packageName] ?? 0,
                                  dragController: dragController,
                                  onTap: () => onAppTap(app),
                                  onLongPress: (pos) => onAppLongPress(app, pos),
                                  onDragStarted: onDragStarted,
                                  onDragEnded: onDragEnded,
                                ),
                              ),
                            )),
                        ...List.generate(
                          settings.drawerColumns - item.apps.length,
                          (_) => const Expanded(child: SizedBox.shrink()),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
              childCount: items.length,
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
  }
}

class _DrawerAppIcon extends StatefulWidget {
  final AppInfo app;
  final LauncherSettings settings;
  final int badgeCount;
  final DragController dragController;
  final VoidCallback onTap;
  final void Function(Offset globalPos) onLongPress;
  final VoidCallback onDragStarted;
  final void Function(bool wasAccepted) onDragEnded;

  const _DrawerAppIcon({
    required this.app,
    required this.settings,
    required this.badgeCount,
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
    );
    final payload = DragPayload(
      item: item,
      sourcePage: kDrawerSourcePage,
      sourceSlot: -1,
    );

    final iconView = BubbleTextView(
      app: widget.app,
      iconSize: widget.settings.drawerIconSize,
      showLabel: widget.settings.showDrawerLabels,
      iconShape: widget.settings.iconShape,
      badgeCount: widget.badgeCount,
    );

    return LongPressDraggable<DragPayload>(
      data: payload,
      delay: const Duration(milliseconds: 350),
      onDragStarted: () {
        // Fires at long-press threshold — show the context menu here.
        // Do NOT navigate yet; wait until the user drags far enough.
        _dragArmed = true;
        _dragMoved = false;
        widget.dragController.startDrag(item, kDrawerSourcePage, -1, Offset.zero);
        if (mounted) setState(() => _dragging = true);
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && mounted) {
          final center = box.localToGlobal(
            Offset(box.size.width / 2, box.size.height / 2),
          );
          _dragStartGlobalPos = center;
          widget.onLongPress(center);
        }
      },
      onDragUpdate: (details) {
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
        _dragArmed = false;
        _dragMoved = false;
        _dragStartGlobalPos = Offset.zero;
        widget.dragController.cancelDrag();
        if (mounted) setState(() => _dragging = false);
        widget.onDragEnded(details.wasAccepted);
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
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: Transform.scale(
            scale: 1.15,
            child: BubbleTextView(
              app: widget.app,
              iconSize: widget.settings.drawerIconSize,
              showLabel: false,
              iconShape: widget.settings.iconShape,
            ),
          ),
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
