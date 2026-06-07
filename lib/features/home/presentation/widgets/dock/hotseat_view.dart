import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_launcher_app/core/models/app_info.dart';
import 'package:smart_launcher_app/core/models/folder_info.dart';
import 'package:smart_launcher_app/core/models/item_info.dart';
import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/core/models/workspace_item_info.dart';
import 'package:smart_launcher_app/features/home/presentation/drag/drag_controller.dart';
import 'package:smart_launcher_app/features/home/presentation/gestures/widget_resize_gesture_guard.dart';
import 'package:smart_launcher_app/features/apps/presentation/bloc/apps_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:smart_launcher_app/features/home/presentation/bloc/workspace_cubit.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/drag/pickup_feedback.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/folder/folder_icon.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/folder/folder_view.dart';
import 'package:smart_launcher_app/core/widgets/icons/badge_listener.dart';
import 'package:smart_launcher_app/core/widgets/icons/bubble_text_view.dart';

const String kDockFolderPrefix = 'folder:';

sealed class DockItem {
  const DockItem();
}

class DockAppItem extends DockItem {
  final AppInfo app;

  const DockAppItem(this.app);
}

class DockFolderItem extends DockItem {
  final String folderId;
  final FolderInfo folder;

  const DockFolderItem({
    required this.folderId,
    required this.folder,
  });
}

class HotseatView extends StatefulWidget {
  final List<DockItem?> apps;
  final LauncherSettings settings;
  final DragController dragController;
  final VoidCallback onSwipeUp;
  final void Function(AppInfo app) onAppTap;
  final void Function(AppInfo app, Offset iconCenter) onAppLongPress;

  const HotseatView({
    super.key,
    required this.apps,
    required this.settings,
    required this.dragController,
    required this.onSwipeUp,
    required this.onAppTap,
    required this.onAppLongPress,
  });

  @override
  State<HotseatView> createState() => _HotseatViewState();
}

class _HotseatViewState extends State<HotseatView> {
  bool _consumeCurrentVerticalSwipe = false;

  bool _consumeEditModeSwipe() {
    if (!WidgetResizeGestureGuard.isResizing) return false;
    _consumeCurrentVerticalSwipe = true;
    if (!WidgetResizeGestureGuard.isHandlePointerActive) {
      WidgetResizeGestureGuard.requestDismiss();
    }
    return true;
  }

  bool _consumeEditModeTap() {
    if (!WidgetResizeGestureGuard.isResizing) return false;
    WidgetResizeGestureGuard.requestDismiss();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.settings.showDock) return const SizedBox.shrink();
    final slotCount =
        widget.settings.dockSize.clamp(0, widget.settings.gridColumns).toInt();

    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(slotCount, (slot) {
        final item = slot < widget.apps.length ? widget.apps[slot] : null;
        return Flexible(
          child: _DockSlot(
            item: item,
            slot: slot,
            apps: widget.apps,
            settings: widget.settings,
            dragController: widget.dragController,
            onAppTap: widget.onAppTap,
            onAppLongPress: widget.onAppLongPress,
            onDismissEditSelection: _consumeEditModeTap,
          ),
        );
      }),
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _consumeEditModeTap,
      onVerticalDragStart: (_) {
        _consumeCurrentVerticalSwipe = false;
        _consumeEditModeSwipe();
      },
      onVerticalDragUpdate: (_) => _consumeEditModeSwipe(),
      onVerticalDragEnd: (d) {
        // While a widget is selected (edit mode) any swipe must
        // dismiss the selection rather than fire the drawer. The dock
        // has its own GestureDetector that bypasses the workspace's
        // Listener path and the cell-layout dismiss catcher, so we
        // route the dismiss through the guard's broadcast hook. Track the
        // whole pointer sequence so a swipe cannot dismiss edit mode on update
        // and then open the drawer on end.
        if (_consumeCurrentVerticalSwipe || _consumeEditModeSwipe()) {
          _consumeCurrentVerticalSwipe = false;
          return;
        }
        if ((d.primaryVelocity ?? 0) < -200) widget.onSwipeUp();
      },
      onVerticalDragCancel: () => _consumeCurrentVerticalSwipe = false,
      child: widget.settings.dockShowBackground
          ? ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: widget.settings.dockBackgroundColor.withValues(
                        alpha: widget.settings.dockBackgroundOpacity),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: row,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: row,
            ),
    );
  }
}

class _DockAppDraggable extends StatefulWidget {
  final AppInfo app;
  final DragPayload payload;
  final LauncherSettings settings;
  final DragController dragController;
  final VoidCallback onPrepareDrag;
  final bool Function() onDismissEditSelection;
  final void Function(AppInfo) onAppTap;
  final void Function(AppInfo, Offset) onAppLongPress;

  const _DockAppDraggable({
    required this.app,
    required this.payload,
    required this.settings,
    required this.dragController,
    required this.onPrepareDrag,
    required this.onDismissEditSelection,
    required this.onAppTap,
    required this.onAppLongPress,
  });

  @override
  State<_DockAppDraggable> createState() => _DockAppDraggableState();
}

class _DockAppDraggableState extends State<_DockAppDraggable> {
  static const double _dragActivationDistance = 24;

  bool _armed = false;
  bool _active = false;
  double _distance = 0;
  final ValueNotifier<bool> _feedbackActive = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _feedbackActive.dispose();
    super.dispose();
  }

  Offset _globalCenter() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    return box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
  }

  void _arm() {
    if (widget.onDismissEditSelection()) return;
    _armed = true;
    _active = false;
    _distance = 0;
    _feedbackActive.value = false;
    widget.onAppLongPress(widget.app, _globalCenter());
  }

  void _maybeActivate(DragUpdateDetails details) {
    if (!_armed) return;
    if (_active) {
      widget.dragController.updateDragPosition(details.globalPosition);
      return;
    }

    _distance += details.delta.distance;
    if (_distance < _dragActivationDistance) return;

    _active = true;
    _feedbackActive.value = true;
    widget.onPrepareDrag();
    widget.dragController.startDrag(
      widget.payload.item,
      widget.payload.sourcePage,
      widget.payload.sourceSlot,
      Offset.zero,
    );
    widget.dragController.updateDragPosition(details.globalPosition);
  }

  void _finish() {
    final wasActive = _active;
    _armed = false;
    _active = false;
    _distance = 0;
    _feedbackActive.value = false;
    if (wasActive) {
      widget.dragController.cancelDrag();
    }
  }

  Widget _icon({required bool dimmed}) {
    final child = BadgeListener(
      packageName: widget.app.packageName,
      builder: (_, badge) => BubbleTextView(
        app: widget.app,
        iconSize: widget.settings.iconSize,
        showLabel: widget.settings.showDockLabels,
        iconShape: widget.settings.iconShape,
        badgeCount: badge,
        onTap: () {
          if (widget.onDismissEditSelection()) return;
          widget.onAppTap(widget.app);
        },
        onLongPress: () {
          if (widget.onDismissEditSelection()) return;
          if (_armed) return;
          widget.onAppLongPress(widget.app, _globalCenter());
        },
      ),
    );
    return dimmed ? Opacity(opacity: 0.3, child: child) : child;
  }

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<DragPayload>(
      data: widget.payload,
      delay: const Duration(milliseconds: 350),
      maxSimultaneousDrags: WidgetResizeGestureGuard.isResizing ? 0 : null,
      onDragStarted: _arm,
      onDragUpdate: _maybeActivate,
      onDragEnd: (_) => _finish(),
      onDraggableCanceled: (_, __) => _finish(),
      feedback: ValueListenableBuilder<bool>(
        valueListenable: _feedbackActive,
        builder: (_, active, __) {
          if (!active) return const SizedBox.shrink();
          return PickupFeedback(
            child: BubbleTextView(
              app: widget.app,
              iconSize: widget.settings.iconSize,
              showLabel: false,
              iconShape: widget.settings.iconShape,
            ),
          );
        },
      ),
      childWhenDragging: ValueListenableBuilder<bool>(
        valueListenable: _feedbackActive,
        builder: (_, active, __) => _icon(dimmed: active),
      ),
      child: _icon(dimmed: false),
    );
  }
}

class _DockSlot extends StatelessWidget {
  final DockItem? item;
  final int slot;
  final List<DockItem?> apps;
  final LauncherSettings settings;
  final DragController dragController;
  final void Function(AppInfo) onAppTap;
  final void Function(AppInfo, Offset) onAppLongPress;
  final bool Function() onDismissEditSelection;

  const _DockSlot({
    required this.item,
    required this.slot,
    required this.apps,
    required this.settings,
    required this.dragController,
    required this.onAppTap,
    required this.onAppLongPress,
    required this.onDismissEditSelection,
  });

  // Writes an app launcher key at position `slot` in dockPackages, expanding the
  // list with empty strings as needed.
  void _setDockSlot(BuildContext context, String launcherKey) {
    final s = context.read<SettingsCubit>().state;
    final packages = _ensureInitialized(s.dockPackages);
    while (packages.length <= slot) {
      packages.add('');
    }
    packages[slot] = launcherKey;
    context.read<SettingsCubit>().update(s.copyWith(dockPackages: packages));
  }

  // Returns a mutable copy of dockPackages, pre-populated from the resolved
  // apps list when the settings list is still empty (never customized).
  List<String> _ensureInitialized(List<String> current) {
    if (current.isNotEmpty) return List<String>.from(current);
    return apps.map((item) {
      if (item is DockAppItem) return item.app.launcherKey;
      if (item is DockFolderItem) return '$kDockFolderPrefix${item.folderId}';
      return '';
    }).toList();
  }

  // Persists the initialized dockPackages if they were not yet saved.
  // Called on drag start so that CellLayoutView._removeDockPackage can find
  // and clear this slot even when dockPackages was still empty.
  void _initDockPackagesIfNeeded(BuildContext context) {
    final s = context.read<SettingsCubit>().state;
    if (s.dockPackages.isEmpty) {
      final packages = _ensureInitialized(s.dockPackages);
      context.read<SettingsCubit>().update(s.copyWith(dockPackages: packages));
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = item;
    final dockIconSize = settings.iconSize;
    final slotWidth = dockIconSize + 16;
    final slotHeight =
        dockIconSize + (settings.showDockLabels ? dockIconSize * 0.6 : 16);

    if (current == null) {
      // Empty dock slot — accepts drops from workspace or other dock slots.
      return DragTarget<DragPayload>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (details) {
          final payload = details.data;
          final pkg = (payload.item is WorkspaceItemInfo)
              ? (payload.item as WorkspaceItemInfo).launcherKey
              : '';
          if (pkg.isEmpty) return;

          _setDockSlot(context, pkg);

          // Remove from workspace source if dragged from workspace
          if (payload.sourcePage >= 0) {
            context
                .read<WorkspaceCubit>()
                .removeItem(payload.sourcePage, payload.sourceSlot);
            context.read<WorkspaceCubit>().collapseEmptyPages();
          }
          // If dragged from another dock slot, clear that slot
          if (payload.sourcePage == -1 && payload.sourceSlot != slot) {
            final s = context.read<SettingsCubit>().state;
            final packages = _ensureInitialized(s.dockPackages);
            while (packages.length <= payload.sourceSlot) {
              packages.add('');
            }
            packages[payload.sourceSlot] = '';
            context
                .read<SettingsCubit>()
                .update(s.copyWith(dockPackages: packages));
          }
        },
        builder: (_, candidateData, __) {
          return SizedBox(
            width: slotWidth,
            height: slotHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onDismissEditSelection,
              child: candidateData.isNotEmpty
                  ? Container(
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    )
                  : const SizedBox.expand(),
            ),
          );
        },
      );
    }

    if (current is DockFolderItem) {
      return _buildFolderSlot(context, current, slotWidth, slotHeight);
    }

    final currentApp = (current as DockAppItem).app;
    final payload = DragPayload(
      item: WorkspaceItemInfo(
        id: currentApp.id,
        itemType: ItemType.application,
        packageName: currentApp.packageName,
        componentName: currentApp.appComponentName,
        title: currentApp.name,
        icon: currentApp.icon,
        iconPath: currentApp.iconPath,
        launcherFeatureId: currentApp.launcherFeatureId,
      ),
      sourcePage: -1, // -1 = dock source
      sourceSlot: slot,
    );

    return DragTarget<DragPayload>(
      // Accept anything except itself
      onWillAcceptWithDetails: (d) =>
          d.data.sourcePage != -1 || d.data.sourceSlot != slot,
      onAcceptWithDetails: (details) {
        final incoming = details.data;
        final incomingRef = (incoming.item is WorkspaceItemInfo)
            ? (incoming.item as WorkspaceItemInfo).launcherKey
            : '';
        if (incomingRef.isEmpty) return;

        // Save the displaced app before overwriting this slot
        final displacedRef = currentApp.launcherKey;

        // Put incoming app into this dock slot
        _setDockSlot(context, incomingRef);

        // Relocate the displaced app to the source location
        if (incoming.sourcePage >= 0) {
          // From workspace — put displaced app back at the source workspace slot
          final workspaceCubit = context.read<WorkspaceCubit>();
          final displacedItem = WorkspaceItemInfo(
            id: currentApp.id,
            itemType: ItemType.application,
            packageName: currentApp.packageName,
            componentName: currentApp.appComponentName,
            title: currentApp.name,
            icon: currentApp.icon,
            iconPath: currentApp.iconPath,
            launcherFeatureId: currentApp.launcherFeatureId,
          );
          workspaceCubit.addItem(
              displacedItem, incoming.sourcePage, incoming.sourceSlot);
        } else if (incoming.sourcePage == -1 && incoming.sourceSlot != slot) {
          // From a different dock slot — swap: put displaced app at source dock slot
          final s = context.read<SettingsCubit>().state;
          final packages = List<String>.from(s.dockPackages);
          while (packages.length <= incoming.sourceSlot) {
            packages.add('');
          }
          packages[incoming.sourceSlot] = displacedRef;
          context
              .read<SettingsCubit>()
              .update(s.copyWith(dockPackages: packages));
        }
      },
      builder: (_, candidateData, __) {
        final isHovered = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: slotWidth,
          height: slotHeight,
          decoration: isHovered
              ? BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: _DockAppDraggable(
            app: currentApp,
            payload: payload,
            settings: settings,
            dragController: dragController,
            onPrepareDrag: () => _initDockPackagesIfNeeded(context),
            onDismissEditSelection: onDismissEditSelection,
            onAppTap: onAppTap,
            onAppLongPress: onAppLongPress,
          ),
        );
      },
    );
  }

  Widget _buildFolderSlot(
    BuildContext context,
    DockFolderItem current,
    double slotWidth,
    double slotHeight,
  ) {
    final folderSettings = settings.copyWith(
      showFolderLabels: settings.showDockLabels,
    );

    return DragTarget<DragPayload>(
      onWillAcceptWithDetails: (d) =>
          d.data.item is WorkspaceItemInfo &&
          (d.data.item as WorkspaceItemInfo).packageName.isNotEmpty,
      onAcceptWithDetails: (details) {
        final item = details.data.item;
        if (item is! WorkspaceItemInfo || item.packageName.isEmpty) return;
        context.read<WorkspaceCubit>().addToFolder(current.folderId, item);

        if (details.data.sourcePage >= 0) {
          context
              .read<WorkspaceCubit>()
              .removeItem(details.data.sourcePage, details.data.sourceSlot);
          context.read<WorkspaceCubit>().collapseEmptyPages();
        } else if (details.data.sourcePage == -1 &&
            details.data.sourceSlot != slot) {
          final s = context.read<SettingsCubit>().state;
          final packages = _ensureInitialized(s.dockPackages);
          while (packages.length <= details.data.sourceSlot) {
            packages.add('');
          }
          packages[details.data.sourceSlot] = '';
          context
              .read<SettingsCubit>()
              .update(s.copyWith(dockPackages: packages));
        } else if (details.data.folderId != null) {
          context
              .read<WorkspaceCubit>()
              .removeFromFolder(details.data.folderId!, item);
          details.data.onFolderDropCompleted?.call();
        }
      },
      builder: (_, candidateData, __) {
        final isHovered = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: slotWidth,
          height: slotHeight,
          decoration: isHovered
              ? BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: Center(
            child: FolderIconView(
              folder: current.folder,
              settings: folderSettings,
              onTap: () {
                if (onDismissEditSelection()) return;
                _openFolder(context, current.folderId);
              },
              onLongPress: onDismissEditSelection,
            ),
          ),
        );
      },
    );
  }

  void _openFolder(BuildContext context, String folderId) {
    final overlay = Overlay.of(context);
    final workspaceCubit = context.read<WorkspaceCubit>();
    final appsCubit = context.read<AppsCubit>();
    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: workspaceCubit),
          BlocProvider.value(value: appsCubit),
        ],
        child: FolderView(
          folderId: folderId,
          folderPage: -1,
          folderSlot: slot,
          settings: settings,
          dragController: dragController,
          onClose: () {
            entry?.remove();
            entry = null;
          },
          onAppTap: (app) {
            entry?.remove();
            entry = null;
            onAppTap(app);
          },
        ),
      ),
    );
    overlay.insert(entry!);
  }
}
