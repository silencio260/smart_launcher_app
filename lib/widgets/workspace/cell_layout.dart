import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../models/folder_info.dart';
import '../../models/item_info.dart';
import '../../models/launcher_settings.dart';
import '../../models/launcher_widget_info.dart';
import '../../models/workspace_item_info.dart';
import '../../services/drag/drag_controller.dart';
import '../../services/launcher_service.dart';
import '../../state/apps_cubit.dart';
import '../../state/settings_cubit.dart';
import '../../state/workspace_cubit.dart';
import '../folder/folder_icon.dart';
import '../folder/folder_view.dart';
import '../icons/bubble_text_view.dart';
import 'home_widget_slot.dart';
import 'home_widget_stack_view.dart';
import 'widget_grid_math.dart';

// sourcePage == -3 means the drag originated from the app drawer (no removal needed)
const int kDrawerSourcePage = -3;

class CellLayoutView extends StatefulWidget {
  final WorkspacePage page;
  final int pageIndex;
  final LauncherSettings settings;
  final DragController dragController;
  final Map<String, int> badgeCounts;
  final void Function(AppInfo app) onAppTap;
  final void Function(AppInfo app, int slot, Offset iconCenter) onAppLongPress;

  const CellLayoutView({
    super.key,
    required this.page,
    required this.pageIndex,
    required this.settings,
    required this.dragController,
    required this.badgeCounts,
    required this.onAppTap,
    required this.onAppLongPress,
  });

  @override
  State<CellLayoutView> createState() => _CellLayoutViewState();
}

class _CellLayoutViewState extends State<CellLayoutView> {
  static const double _gridGap = 8;
  int? _draggingSlot;

  // Tracks per-slot timers for app displacement during widget hover
  final Map<int, Timer> _displacementTimers = {};

  @override
  void dispose() {
    _cancelAllDisplacementTimers();
    super.dispose();
  }

  void _cancelAllDisplacementTimers() {
    for (final t in _displacementTimers.values) {
      t.cancel();
    }
    _displacementTimers.clear();
  }

  void _startDisplacementTimer(
      int slot, WorkspaceCubit workspace, LauncherSettings settings) {
    if (_displacementTimers.containsKey(slot)) return;
    _displacementTimers[slot] = Timer(const Duration(milliseconds: 240), () {
      _displacementTimers.remove(slot);
      _tryDisplaceApp(slot, workspace, settings);
    });
  }

  void _cancelDisplacementTimer(int slot) {
    _displacementTimers[slot]?.cancel();
    _displacementTimers.remove(slot);
  }

  bool _tryDisplaceApp(
    int appSlot,
    WorkspaceCubit workspace,
    LauncherSettings settings, {
    int? ignoreSlot,
  }) {
    final path = _findDisplacementPath(
      appSlot,
      settings.gridColumns,
      settings.gridRows,
      ignoreSlot: ignoreSlot,
    );
    if (path == null) return false;

    if (workspace.shiftItemsAlongPath(widget.pageIndex, path)) {
      for (int i = 0; i < path.length - 1; i++) {
        widget.dragController.recordDisplacement(
          widget.pageIndex,
          path[i],
          path[i + 1],
        );
      }
      return true;
    }
    return false;
  }

  /// Returns the set of grid slots currently occupied by the widget being
  /// dragged, if the drag originated on this page. Used to distinguish
  /// "covered by the source widget itself" from "covered by another widget",
  /// so those slots can still receive DragTargets and be accepted as drops.
  Set<int> _sourceWidgetCoverage(DragPayload? payload) {
    if (payload == null || !payload.isWidget) return const {};
    if (payload.sourcePage != widget.pageIndex) return const {};
    final sourceContent = widget.page.slots[payload.sourceSlot];
    final (spanX, spanY) = switch (sourceContent) {
      WidgetSlot(:final widget) => (widget.spanX, widget.spanY),
      WidgetStackSlot(:final spanX, :final spanY) => (spanX, spanY),
      _ => (0, 0),
    };
    if (spanX == 0 || spanY == 0) return const {};
    return {
      ...?slotsForSpan(
        payload.sourceSlot,
        spanX.clamp(1, widget.settings.gridColumns),
        spanY.clamp(1, widget.settings.gridRows),
        widget.settings.gridColumns,
        widget.settings.gridRows,
      ),
    };
  }

  List<int> _adjacentSlots(int slot, int cols, int rows) {
    final total = cols * rows;
    final col = slot % cols;
    final result = <int>[];
    if (col < cols - 1) result.add(slot + 1); // right
    if (col > 0) result.add(slot - 1); // left
    if (slot + cols < total) result.add(slot + cols); // below
    if (slot - cols >= 0) result.add(slot - cols); // above
    return result;
  }

  List<int>? _findDisplacementPath(
    int startSlot,
    int cols,
    int rows, {
    int? ignoreSlot,
    // Pass the live workspace page when calling from _onDrop after earlier
    // displacements have already shifted slots — widget.page is stale then.
    WorkspacePage? page,
  }) {
    final sourcePage = page ?? widget.page;
    final coveredSlots = occupiedWidgetSlots(
      sourcePage,
      cols,
      rows,
      ignoreAnchorSlot: ignoreSlot,
    );
    final queue = <int>[startSlot];
    final previous = <int, int?>{startSlot: null};

    while (queue.isNotEmpty) {
      final slot = queue.removeAt(0);
      for (final next in _adjacentSlots(slot, cols, rows)) {
        if (previous.containsKey(next)) continue;
        if (coveredSlots.contains(next)) continue;

        final content = next == ignoreSlot ? null : sourcePage.slots[next];
        if (content is WidgetSlot || content is WidgetStackSlot) continue;

        previous[next] = slot;
        if (content == null || content is EmptySlot) {
          final path = <int>[next];
          int? cursor = slot;
          while (cursor != null) {
            path.add(cursor);
            cursor = previous[cursor];
          }
          return path.reversed.toList();
        }

        queue.add(next);
      }
    }

    return null;
  }

  void _removeDockPackage(BuildContext context, int dockSlot) {
    final settings = context.read<SettingsCubit>().state;
    final packages = List<String>.from(settings.dockPackages);
    if (dockSlot < packages.length) packages[dockSlot] = '';
    context
        .read<SettingsCubit>()
        .update(settings.copyWith(dockPackages: packages));
  }

  void _onDrop(
      BuildContext context, DragTargetDetails<DragPayload> details, int slot) {
    // Always commit displacements on any successful drop
    widget.dragController.commitDisplacements();
    _cancelAllDisplacementTimers();

    final payload = details.data;
    final target = widget.page.slots[slot];
    final workspace = context.read<WorkspaceCubit>();

    // ── Widget drag ────────────────────────────────────────────────────────────
    if (payload.isWidget) {
      if (target is WidgetSlot || target is WidgetStackSlot) {
        // Stack the two widgets together
        workspace.createWidgetStack(
            payload.sourcePage, payload.sourceSlot, widget.pageIndex, slot);
      } else if (target is AppSlot) {
        final settings = context.read<SettingsCubit>().state;
        final path = _findDisplacementPath(
          slot,
          settings.gridColumns,
          settings.gridRows,
          ignoreSlot: payload.sourcePage == widget.pageIndex
              ? payload.sourceSlot
              : null,
        );
        if (path == null ||
            !workspace.moveItemWithDisplacement(
              payload.sourcePage,
              payload.sourceSlot,
              widget.pageIndex,
              slot,
              path,
            )) {
          widget.dragController.cancelDrag();
          return;
        }
      } else {
        // Empty slot (or a slot that was in the source widget's coverage).
        // First displace any apps that sit inside the widget's target span —
        // this handles the case where _willAccept accepted a span with apps.
        final settings = context.read<SettingsCubit>().state;
        final cols = settings.gridColumns;
        final rows = settings.gridRows;
        final sourceContent =
            workspace.state.pages[payload.sourcePage].slots[payload.sourceSlot];
        final (spanX, spanY) = switch (sourceContent) {
          WidgetSlot(:final widget) => (widget.spanX, widget.spanY),
          WidgetStackSlot(:final spanX, :final spanY) => (spanX, spanY),
          _ => (1, 1),
        };
        final ignoreSource =
            payload.sourcePage == widget.pageIndex ? payload.sourceSlot : null;
        final targetCovered =
            slotsForSpan(slot, spanX, spanY, cols, rows) ?? const [];
        for (final targetSlot in targetCovered) {
          if (targetSlot == ignoreSource) continue;
          // Re-read the live page each iteration because earlier iterations
          // may have shifted items.
          final livePage = workspace.state.pages[widget.pageIndex];
          final slotContent = livePage.slots[targetSlot];
          if (slotContent is AppSlot) {
            final path = _findDisplacementPath(
              targetSlot,
              cols,
              rows,
              ignoreSlot: ignoreSource,
              page: livePage,
            );
            if (path != null) {
              workspace.shiftItemsAlongPath(widget.pageIndex, path);
              for (int i = 0; i < path.length - 1; i++) {
                widget.dragController
                    .recordDisplacement(widget.pageIndex, path[i], path[i + 1]);
              }
            }
          }
        }
        workspace.moveItem(
            payload.sourcePage, payload.sourceSlot, widget.pageIndex, slot);
      }
      workspace.collapseEmptyPages();
      widget.dragController.cancelDrag();
      return;
    }

    // ── Normal app/folder drag ─────────────────────────────────────────────────

    if (payload.folderId != null) {
      final item = payload.item;
      if (item is WorkspaceItemInfo) {
        if (target is FolderSlot) {
          workspace.addToFolder(target.folderId, item);
        } else {
          workspace.addItem(item, widget.pageIndex, slot);
        }
        workspace.removeFromFolder(payload.folderId!, item.id);
        final remaining =
            workspace.state.folders[payload.folderId!]?.contents.length ?? 0;
        if (remaining <= 1) {
          workspace.tryCollapseFolder(
              payload.folderId!, payload.folderPage, payload.folderSlot);
        }
      }
      workspace.collapseEmptyPages();
      widget.dragController.cancelDrag();
      return;
    }

    if (payload.sourcePage == kDrawerSourcePage) {
      final item = payload.item;
      if (item is WorkspaceItemInfo) {
        if (target is FolderSlot) {
          workspace.addToFolder(target.folderId, item);
        } else if (target is AppSlot) {
          final settings = context.read<SettingsCubit>().state;
          if (!_tryDisplaceApp(slot, workspace, settings)) {
            widget.dragController.cancelDrag();
            return;
          }
          workspace.addItem(item, widget.pageIndex, slot);
        } else {
          workspace.addItem(item, widget.pageIndex, slot);
        }
        workspace.collapseEmptyPages();
      }
      widget.dragController.cancelDrag();
      return;
    }

    if (target is FolderSlot) {
      final item = payload.item;
      if (item is WorkspaceItemInfo && item.itemType == ItemType.application) {
        final added = workspace.addToFolder(target.folderId, item);
        if (added) {
          if (payload.sourcePage >= 0) {
            workspace.removeItem(payload.sourcePage, payload.sourceSlot);
          } else if (payload.sourcePage == -1) {
            _removeDockPackage(context, payload.sourceSlot);
          }
        }
      } else {
        if (payload.sourcePage >= 0) {
          workspace.moveItem(
              payload.sourcePage, payload.sourceSlot, widget.pageIndex, slot);
        }
      }
    } else if (target is AppSlot && payload.sourcePage >= 0) {
      final settings = context.read<SettingsCubit>().state;
      final path = _findDisplacementPath(
        slot,
        settings.gridColumns,
        settings.gridRows,
        ignoreSlot:
            payload.sourcePage == widget.pageIndex ? payload.sourceSlot : null,
      );
      if (path == null ||
          !workspace.moveItemWithDisplacement(
            payload.sourcePage,
            payload.sourceSlot,
            widget.pageIndex,
            slot,
            path,
          )) {
        widget.dragController.cancelDrag();
        return;
      }
    } else {
      if (payload.sourcePage >= 0) {
        workspace.moveItem(
            payload.sourcePage, payload.sourceSlot, widget.pageIndex, slot);
      } else if (payload.sourcePage == -1) {
        final item = payload.item;
        if (item is WorkspaceItemInfo) {
          workspace.addItem(item, widget.pageIndex, slot);
          _removeDockPackage(context, payload.sourceSlot);
        }
      }
    }

    workspace.collapseEmptyPages();
    widget.dragController.cancelDrag();
  }

  bool _willAccept(
    DragPayload payload,
    SlotContent? target,
    int slot,
    WorkspaceCubit workspace,
  ) {
    final coveredSlots = occupiedWidgetSlots(
      widget.page,
      widget.settings.gridColumns,
      widget.settings.gridRows,
    );
    final isWidgetAnchor = target is WidgetSlot || target is WidgetStackSlot;

    // Slots covered by the SOURCE widget being dragged must not be treated as
    // "covered by another widget" — they will be freed once the widget moves.
    final sourceWidgetCoverage = _sourceWidgetCoverage(payload);
    final isCoveredByAnotherWidget = coveredSlots.contains(slot) &&
        !isWidgetAnchor &&
        !sourceWidgetCoverage.contains(slot);

    // Reject same-slot drops
    if (payload.sourcePage == widget.pageIndex && payload.sourceSlot == slot) {
      return false;
    }
    if (isCoveredByAnotherWidget) return false;
    if (!payload.isWidget && isWidgetAnchor) return false;

    if (payload.isWidget) {
      if (target is FolderSlot) return false;
      if (target is AppSlot) {
        return _findDisplacementPath(
              slot,
              widget.settings.gridColumns,
              widget.settings.gridRows,
              ignoreSlot: payload.sourcePage == widget.pageIndex
                  ? payload.sourceSlot
                  : null,
            ) !=
            null;
      }
      if (isWidgetAnchor) return true;

      final sourcePage = payload.sourcePage >= 0 &&
              payload.sourcePage < workspace.state.pages.length
          ? workspace.state.pages[payload.sourcePage]
          : null;
      final sourceContent = sourcePage?.slots[payload.sourceSlot];
      final (spanX, spanY) = switch (sourceContent) {
        WidgetSlot(:final widget) => (widget.spanX, widget.spanY),
        WidgetStackSlot(:final spanX, :final spanY) => (spanX, spanY),
        _ => (1, 1),
      };

      // More permissive than canPlaceWidgetAt: apps in the target span are OK
      // because they will be displaced at drop time. Only other widgets and
      // folders are hard blockers.
      return _canPlaceWidgetAllowingAppDisplacement(
        anchorSlot: slot,
        spanX: spanX,
        spanY: spanY,
        ignoreAnchorSlot:
            payload.sourcePage == widget.pageIndex ? payload.sourceSlot : null,
      );
    }
    if (target is AppSlot) {
      return _findDisplacementPath(
            slot,
            widget.settings.gridColumns,
            widget.settings.gridRows,
            ignoreSlot: payload.sourcePage == widget.pageIndex
                ? payload.sourceSlot
                : null,
          ) !=
          null;
    }
    return true;
  }

  /// Like [canPlaceWidgetAt] but treats app-occupied slots as valid — those
  /// apps will be displaced when the widget is dropped. Only another widget
  /// or a folder hard-blocks the placement.
  bool _canPlaceWidgetAllowingAppDisplacement({
    required int anchorSlot,
    required int spanX,
    required int spanY,
    int? ignoreAnchorSlot,
  }) {
    final covered = slotsForSpan(
      anchorSlot,
      spanX,
      spanY,
      widget.settings.gridColumns,
      widget.settings.gridRows,
    );
    if (covered == null) return false;

    final ignoredCoverage = ignoreAnchorSlot == null
        ? const <int>{}
        : currentWidgetCoverage(
            widget.page,
            ignoreAnchorSlot,
            widget.settings.gridColumns,
            widget.settings.gridRows,
          );
    final occupiedByOtherWidgets = occupiedWidgetSlots(
      widget.page,
      widget.settings.gridColumns,
      widget.settings.gridRows,
      ignoreAnchorSlot: ignoreAnchorSlot,
    );

    for (final s in covered) {
      if (occupiedByOtherWidgets.contains(s)) return false;
      if (ignoredCoverage.contains(s)) continue;
      final content = widget.page.slots[s];
      if (content is FolderSlot) return false;
      // AppSlot and empty are fine — apps displaced at drop time.
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final appsState = context.watch<AppsCubit>().state;
    final totalSlots = widget.settings.gridColumns * widget.settings.gridRows;
    final coveredSlots = occupiedWidgetSlots(
      widget.page,
      widget.settings.gridColumns,
      widget.settings.gridRows,
    );

    return Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = widget.settings.gridColumns;
          final rows = widget.settings.gridRows;
          final cellWidth =
              (constraints.maxWidth - (columns - 1) * _gridGap) / columns;
          final cellHeight =
              (constraints.maxHeight - (rows - 1) * _gridGap) / rows;

          return Stack(
            children: [
              if (widget.settings.showGridDebugOverlay)
                ...List.generate(totalSlots, (slot) {
                  final content = widget.page.slots[slot];
                  final isWidgetAnchor =
                      content is WidgetSlot || content is WidgetStackSlot;
                  final isCoveredByWidget =
                      coveredSlots.contains(slot) && !isWidgetAnchor;
                  final isEmpty = !isCoveredByWidget &&
                      (content == null || content is EmptySlot);
                  final rect = _slotRect(slot, cellWidth, cellHeight);

                  return Positioned(
                    left: rect.left,
                    top: rect.top,
                    width: rect.width,
                    height: rect.height,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isEmpty
                              ? Colors.green.withValues(alpha: 0.14)
                              : Colors.red.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isEmpty
                                ? Colors.greenAccent.withValues(alpha: 0.9)
                                : Colors.redAccent.withValues(alpha: 0.9),
                          ),
                        ),
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          '$slot',
                          style: TextStyle(
                            color: isEmpty
                                ? Colors.greenAccent.shade100
                                : Colors.redAccent.shade100,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              for (int slot = 0; slot < totalSlots; slot++)
                ..._buildPositionedContent(
                  context,
                  slot,
                  appsState,
                  coveredSlots,
                  cellWidth,
                  cellHeight,
                ),
              ListenableBuilder(
                listenable: widget.dragController,
                builder: (context, _) {
                  if (!widget.dragController.isDragging) {
                    return const SizedBox.shrink();
                  }

                  final workspace = context.read<WorkspaceCubit>();
                  // When dragging a widget, its own coverage slots will be
                  // freed on drop and must still receive DragTargets so the
                  // widget can be moved to partially-overlapping positions.
                  final sourceWidgetCoverage =
                      _sourceWidgetCoverage(widget.dragController.activeDrag);
                  return Stack(
                    children: List.generate(totalSlots, (slot) {
                      final content = widget.page.slots[slot];
                      final isWidgetAnchor =
                          content is WidgetSlot || content is WidgetStackSlot;
                      final coveredByOtherWidget = coveredSlots.contains(slot) &&
                          !isWidgetAnchor &&
                          !sourceWidgetCoverage.contains(slot);
                      if (coveredByOtherWidget) {
                        return const SizedBox.shrink();
                      }

                      final rect = _slotRect(slot, cellWidth, cellHeight);
                      return Positioned(
                        left: rect.left,
                        top: rect.top,
                        width: rect.width,
                        height: rect.height,
                        child: DragTarget<DragPayload>(
                          onWillAcceptWithDetails: (d) =>
                              _willAccept(d.data, content, slot, workspace),
                          onAcceptWithDetails: (d) => _onDrop(context, d, slot),
                          onMove: (details) {
                            if (details.data.isWidget && content is AppSlot) {
                              final settings =
                                  context.read<SettingsCubit>().state;
                              _startDisplacementTimer(
                                  slot, workspace, settings);
                            }
                          },
                          onLeave: (_) => _cancelDisplacementTimer(slot),
                          builder: (context, candidateData, _) {
                            final isHovered = candidateData.isNotEmpty;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: isHovered
                                  ? BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white24),
                                    )
                                  : null,
                            );
                          },
                        ),
                      );
                    }),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildPositionedContent(
    BuildContext context,
    int slot,
    AppsState appsState,
    Set<int> coveredSlots,
    double cellWidth,
    double cellHeight,
  ) {
    final content = widget.page.slots[slot];
    final isCoveredByAnotherWidget = coveredSlots.contains(slot) &&
        content is! WidgetSlot &&
        content is! WidgetStackSlot;
    if (isCoveredByAnotherWidget) return const [];
    if (content == null || content is EmptySlot) return const [];

    if (content is WidgetSlot) {
      final spanX =
          content.widget.spanX.clamp(1, widget.settings.gridColumns).toInt();
      final spanY =
          content.widget.spanY.clamp(1, widget.settings.gridRows).toInt();
      return [
        _positionedForSpan(
          slot,
          spanX,
          spanY,
          cellWidth,
          cellHeight,
          _buildWidgetSlot(context, content, slot),
        ),
      ];
    }

    if (content is WidgetStackSlot) {
      final spanX = content.spanX.clamp(1, widget.settings.gridColumns).toInt();
      final spanY = content.spanY.clamp(1, widget.settings.gridRows).toInt();
      return [
        _positionedForSpan(
          slot,
          spanX,
          spanY,
          cellWidth,
          cellHeight,
          _buildWidgetStackSlot(context, content, slot),
        ),
      ];
    }

    return [
      Positioned(
        left: _slotRect(slot, cellWidth, cellHeight).left,
        top: _slotRect(slot, cellWidth, cellHeight).top,
        width: cellWidth,
        height: cellHeight,
        child: _buildSlotContent(context, content, slot, appsState),
      ),
    ];
  }

  Positioned _positionedForSpan(
    int slot,
    int spanX,
    int spanY,
    double cellWidth,
    double cellHeight,
    Widget child,
  ) {
    final rect = _slotRect(slot, cellWidth, cellHeight);
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: cellWidth * spanX + _gridGap * (spanX - 1),
      height: cellHeight * spanY + _gridGap * (spanY - 1),
      child: child,
    );
  }

  Rect _slotRect(int slot, double cellWidth, double cellHeight) {
    final column = slot % widget.settings.gridColumns;
    final row = slot ~/ widget.settings.gridColumns;
    return Rect.fromLTWH(
      column * (cellWidth + _gridGap),
      row * (cellHeight + _gridGap),
      cellWidth,
      cellHeight,
    );
  }

  Widget _buildSlotContent(
    BuildContext context,
    SlotContent? content,
    int slot,
    AppsState appsState,
  ) {
    if (content == null || content is EmptySlot) {
      return const SizedBox.shrink();
    }

    if (content is WidgetSlot) {
      return _buildWidgetSlot(context, content, slot);
    }

    if (content is WidgetStackSlot) {
      return _buildWidgetStackSlot(context, content, slot);
    }

    if (content is AppSlot) {
      return _buildAppSlot(context, content, slot, appsState);
    }

    if (content is FolderSlot) {
      return _buildFolderSlot(context, content, slot, appsState);
    }

    return const SizedBox.shrink();
  }

  Widget _buildWidgetSlot(BuildContext context, WidgetSlot content, int slot) {
    final w = content.widget;
    final maxSpanX =
        _maxHorizontalSpan(slot, currentSpanY: w.spanY, ignoreAnchorSlot: slot);
    final maxSpanY =
        _maxVerticalSpan(slot, currentSpanX: w.spanX, ignoreAnchorSlot: slot);
    final payload = DragPayload(
      item: WorkspaceItemInfo(
        id: w.id,
        itemType: ItemType.appWidget,
        packageName: w.providerPackage,
        componentName: w.providerClass,
        title: 'Widget',
      ),
      sourcePage: widget.pageIndex,
      sourceSlot: slot,
    );

    return LongPressDraggable<DragPayload>(
      data: payload,
      rootOverlay: true,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      delay: const Duration(milliseconds: 350),
      onDragStarted: () {
        setState(() => _draggingSlot = slot);
        widget.dragController
            .startDrag(payload.item, widget.pageIndex, slot, Offset.zero);
      },
      onDragEnd: (_) {
        setState(() => _draggingSlot = null);
        _cancelAllDisplacementTimers();
        widget.dragController.cancelDrag();
      },
      onDraggableCanceled: (_, __) {
        setState(() => _draggingSlot = null);
        _cancelAllDisplacementTimers();
        widget.dragController.cancelDrag();
      },
      onDragCompleted: () {
        setState(() => _draggingSlot = null);
        _cancelAllDisplacementTimers();
      },
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.8,
          child: Container(
            width: 120,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white38),
            ),
            child: const Center(
              child:
                  Icon(Icons.widgets_outlined, color: Colors.white70, size: 36),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.12,
        child: HomeWidgetSlot(
          widget: w,
          page: widget.pageIndex,
          slot: slot,
          minSpanX: _minSpanXForWidget(w),
          minSpanY: _minSpanYForWidget(w),
          maxSpanX: math.max(_minSpanXForWidget(w), maxSpanX),
          maxSpanY: math.max(_minSpanYForWidget(w), maxSpanY),
          gridColumns: widget.settings.gridColumns,
          onResize: (nextSlot, nextSpanX, nextSpanY) =>
              _resizeWidget(slot, w, nextSlot, nextSpanX, nextSpanY),
        ),
      ),
      child: HomeWidgetSlot(
        widget: w,
        page: widget.pageIndex,
        slot: slot,
        minSpanX: _minSpanXForWidget(w),
        minSpanY: _minSpanYForWidget(w),
        maxSpanX: math.max(_minSpanXForWidget(w), maxSpanX),
        maxSpanY: math.max(_minSpanYForWidget(w), maxSpanY),
        gridColumns: widget.settings.gridColumns,
        onResize: (nextSlot, nextSpanX, nextSpanY) =>
            _resizeWidget(slot, w, nextSlot, nextSpanX, nextSpanY),
      ),
    );
  }

  Widget _buildWidgetStackSlot(
      BuildContext context, WidgetStackSlot content, int slot) {
    final maxSpanX = _maxHorizontalSpan(
      slot,
      currentSpanY: content.spanY,
      ignoreAnchorSlot: slot,
    );
    final maxSpanY = _maxVerticalSpan(
      slot,
      currentSpanX: content.spanX,
      ignoreAnchorSlot: slot,
    );
    final minSpanX = content.widgets.fold<int>(
      1,
      (value, widget) => math.max(value, _minSpanXForWidget(widget)),
    );
    final minSpanY = content.widgets.fold<int>(
      1,
      (value, widget) => math.max(value, _minSpanYForWidget(widget)),
    );
    // Use first widget to build a representative drag payload
    final first = content.widgets.first;
    final payload = DragPayload(
      item: WorkspaceItemInfo(
        id: first.id,
        itemType: ItemType.appWidget,
        packageName: first.providerPackage,
        componentName: first.providerClass,
        title: 'Widget Stack',
      ),
      sourcePage: widget.pageIndex,
      sourceSlot: slot,
    );

    return LongPressDraggable<DragPayload>(
      data: payload,
      rootOverlay: true,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      delay: const Duration(milliseconds: 350),
      onDragStarted: () {
        setState(() => _draggingSlot = slot);
        widget.dragController
            .startDrag(payload.item, widget.pageIndex, slot, Offset.zero);
      },
      onDragEnd: (_) {
        setState(() => _draggingSlot = null);
        _cancelAllDisplacementTimers();
        widget.dragController.cancelDrag();
      },
      onDraggableCanceled: (_, __) {
        setState(() => _draggingSlot = null);
        _cancelAllDisplacementTimers();
        widget.dragController.cancelDrag();
      },
      onDragCompleted: () {
        setState(() => _draggingSlot = null);
        _cancelAllDisplacementTimers();
      },
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.8,
          child: Container(
            width: 120,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white38),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.widgets_outlined,
                      color: Colors.white70, size: 28),
                  Text(
                    '${content.widgets.length}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.12,
        child: HomeWidgetStackView(
          widgets: content.widgets,
          spanX: content.spanX,
          spanY: content.spanY,
          page: widget.pageIndex,
          slot: slot,
          minSpanX: minSpanX,
          minSpanY: minSpanY,
          maxSpanX: math.max(minSpanX, maxSpanX),
          maxSpanY: math.max(minSpanY, maxSpanY),
          gridColumns: widget.settings.gridColumns,
          onResize: (nextSlot, nextSpanX, nextSpanY) =>
              _resizeWidgetStack(slot, content, nextSlot, nextSpanX, nextSpanY),
        ),
      ),
      child: HomeWidgetStackView(
        widgets: content.widgets,
        spanX: content.spanX,
        spanY: content.spanY,
        page: widget.pageIndex,
        slot: slot,
        minSpanX: minSpanX,
        minSpanY: minSpanY,
        maxSpanX: math.max(minSpanX, maxSpanX),
        maxSpanY: math.max(minSpanY, maxSpanY),
        gridColumns: widget.settings.gridColumns,
        onResize: (nextSlot, nextSpanX, nextSpanY) =>
            _resizeWidgetStack(slot, content, nextSlot, nextSpanX, nextSpanY),
      ),
    );
  }

  Widget _buildAppSlot(
      BuildContext context, AppSlot content, int slot, AppsState appsState) {
    final item = content.item;
    final liveApp = appsState.apps
        .where((a) => a.packageName == item.packageName)
        .firstOrNull;
    final app = AppInfo(
      id: item.id,
      packageName: item.packageName,
      appComponentName:
          item.componentName ?? liveApp?.appComponentName ?? item.packageName,
      title: item.title ?? liveApp?.name,
      icon: liveApp?.icon ?? item.icon,
    );

    final badge = widget.badgeCounts[item.packageName] ?? 0;
    final payload =
        DragPayload(item: item, sourcePage: widget.pageIndex, sourceSlot: slot);

    return Center(
      child: LongPressDraggable<DragPayload>(
        data: payload,
        delay: const Duration(milliseconds: 350),
        onDragStarted: () {
          setState(() => _draggingSlot = slot);
          widget.dragController
              .startDrag(item, widget.pageIndex, slot, Offset.zero);
        },
        onDragCompleted: () {
          setState(() => _draggingSlot = null);
        },
        onDragEnd: (_) {
          setState(() => _draggingSlot = null);
          widget.dragController.cancelDrag();
        },
        onDraggableCanceled: (_, __) {
          setState(() => _draggingSlot = null);
          widget.dragController.cancelDrag();
        },
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.85,
            child: Transform.scale(
              scale: 1.15,
              child: BubbleTextView(
                app: app,
                iconSize: widget.settings.iconSize,
                showLabel: false,
                iconShape: widget.settings.iconShape,
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: BubbleTextView(
            app: app,
            iconSize: widget.settings.iconSize,
            showLabel: widget.settings.showLabels,
            labelSize: widget.settings.labelSize,
            iconShape: widget.settings.iconShape,
            badgeCount: badge,
          ),
        ),
        child: BubbleTextView(
          app: app,
          iconSize: widget.settings.iconSize,
          showLabel: widget.settings.showLabels,
          labelSize: widget.settings.labelSize,
          iconShape: widget.settings.iconShape,
          badgeCount: badge,
          onTap: () => widget.onAppTap(app),
          onLongPress: _draggingSlot == slot
              ? null
              : () {
                  final box = context.findRenderObject() as RenderBox?;
                  final center = box == null
                      ? Offset.zero
                      : box.localToGlobal(
                          Offset(box.size.width / 2, box.size.height / 2));
                  widget.onAppLongPress(app, slot, center);
                },
        ),
      ),
    );
  }

  Widget _buildFolderSlot(
      BuildContext context, FolderSlot content, int slot, AppsState appsState) {
    final folders = context.watch<WorkspaceCubit>().state.folders;
    final folder = folders[content.folderId];
    if (folder == null) return const SizedBox.shrink();

    final resolvedFolder = _resolveFolderIcons(folder, appsState);

    return Center(
      child: LongPressDraggable<DragPayload>(
        data: DragPayload(
          item: WorkspaceItemInfo(
            id: folder.id,
            itemType: ItemType.folder,
            packageName: '',
            title: folder.folderTitle,
          ),
          sourcePage: widget.pageIndex,
          sourceSlot: slot,
        ),
        delay: const Duration(milliseconds: 350),
        onDragStarted: () {
          setState(() => _draggingSlot = slot);
          widget.dragController.startDrag(
              WorkspaceItemInfo(
                id: folder.id,
                itemType: ItemType.folder,
                packageName: '',
                title: folder.folderTitle,
              ),
              widget.pageIndex,
              slot,
              Offset.zero);
        },
        onDragCompleted: () {
          setState(() => _draggingSlot = null);
        },
        onDragEnd: (_) {
          setState(() => _draggingSlot = null);
          widget.dragController.cancelDrag();
        },
        onDraggableCanceled: (_, __) {
          setState(() => _draggingSlot = null);
          widget.dragController.cancelDrag();
        },
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.85,
            child: Transform.scale(
              scale: 1.15,
              child: FolderIconView(
                folder: resolvedFolder,
                settings: widget.settings,
                onTap: () {},
                onLongPress: () {},
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: FolderIconView(
            folder: resolvedFolder,
            settings: widget.settings,
            onTap: () {},
            onLongPress: () {},
          ),
        ),
        child: FolderIconView(
          folder: resolvedFolder,
          settings: widget.settings,
          badgeCount: 0,
          onTap: () => _openFolder(context, content.folderId, slot),
          onLongPress: _draggingSlot == slot ? () {} : () {},
        ),
      ),
    );
  }

  FolderInfo _resolveFolderIcons(FolderInfo folder, AppsState appsState) {
    final resolved = folder.contents.map((item) {
      if (item.icon != null) return item;
      final live = appsState.apps
          .where((a) => a.packageName == item.packageName)
          .firstOrNull;
      if (live == null) return item;
      return WorkspaceItemInfo(
        id: item.id,
        itemType: item.itemType,
        packageName: item.packageName,
        componentName: item.componentName ?? live.appComponentName,
        title: item.title ?? live.name,
        icon: live.icon,
      );
    }).toList();
    return FolderInfo(
      id: folder.id,
      folderTitle: folder.folderTitle,
      contents: resolved,
      cellX: folder.cellX,
      cellY: folder.cellY,
      screenId: folder.screenId,
    );
  }

  void _openFolder(BuildContext context, String folderId, int slot) {
    final overlay = Overlay.of(context);
    final workspaceCubit = context.read<WorkspaceCubit>();
    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (overlayCtx) => BlocProvider.value(
        value: workspaceCubit,
        child: FolderView(
          folderId: folderId,
          folderPage: widget.pageIndex,
          folderSlot: slot,
          settings: widget.settings,
          badgeCounts: widget.badgeCounts,
          onClose: () {
            entry?.remove();
            entry = null;
          },
          onAppTap: (app) {
            entry?.remove();
            entry = null;
            LauncherService.launchApp(app.packageName);
          },
        ),
      ),
    );
    overlay.insert(entry!);
  }

  int _minSpanXForWidget(LauncherWidgetInfo widgetInfo) {
    final sourceWidth = widgetInfo.minResizeWidth > 0
        ? widgetInfo.minResizeWidth
        : widgetInfo.minWidth;
    if (sourceWidth <= 0) return 1;
    return (sourceWidth / 110).ceil().clamp(1, widget.settings.gridColumns);
  }

  int _minSpanYForWidget(LauncherWidgetInfo widgetInfo) {
    final sourceHeight = widgetInfo.minResizeHeight > 0
        ? widgetInfo.minResizeHeight
        : widgetInfo.minHeight;
    if (sourceHeight <= 0) return 1;
    return (sourceHeight / 110).ceil().clamp(1, widget.settings.gridRows);
  }

  int _maxHorizontalSpan(
    int slot, {
    required int currentSpanY,
    required int ignoreAnchorSlot,
  }) {
    int maxSpan = 1;
    for (int span = 1; span <= widget.settings.gridColumns; span++) {
      if (canPlaceWidgetAt(
        widget.page,
        slot,
        span,
        currentSpanY,
        widget.settings.gridColumns,
        widget.settings.gridRows,
        ignoreAnchorSlot: ignoreAnchorSlot,
      )) {
        maxSpan = span;
      } else {
        break;
      }
    }
    return maxSpan;
  }

  int _maxVerticalSpan(
    int slot, {
    required int currentSpanX,
    required int ignoreAnchorSlot,
  }) {
    int maxSpan = 1;
    for (int span = 1; span <= widget.settings.gridRows; span++) {
      if (canPlaceWidgetAt(
        widget.page,
        slot,
        currentSpanX,
        span,
        widget.settings.gridColumns,
        widget.settings.gridRows,
        ignoreAnchorSlot: ignoreAnchorSlot,
      )) {
        maxSpan = span;
      } else {
        break;
      }
    }
    return maxSpan;
  }

  void _resizeWidget(
    int currentSlot,
    LauncherWidgetInfo widgetInfo,
    int nextSlot,
    int nextSpanX,
    int nextSpanY,
  ) {
    if (!canPlaceWidgetAt(
      widget.page,
      nextSlot,
      nextSpanX,
      nextSpanY,
      widget.settings.gridColumns,
      widget.settings.gridRows,
      ignoreAnchorSlot: currentSlot,
    )) {
      return;
    }

    final workspace = context.read<WorkspaceCubit>();
    final updated = widgetInfo.copyWith(spanX: nextSpanX, spanY: nextSpanY);
    if (currentSlot == nextSlot) {
      workspace.updateWidgetSpan(widget.pageIndex, currentSlot, updated);
      return;
    }

    workspace.moveItem(
        widget.pageIndex, currentSlot, widget.pageIndex, nextSlot);
    workspace.updateWidgetSpan(widget.pageIndex, nextSlot, updated);
  }

  void _resizeWidgetStack(
    int currentSlot,
    WidgetStackSlot stack,
    int nextSlot,
    int nextSpanX,
    int nextSpanY,
  ) {
    if (!canPlaceWidgetAt(
      widget.page,
      nextSlot,
      nextSpanX,
      nextSpanY,
      widget.settings.gridColumns,
      widget.settings.gridRows,
      ignoreAnchorSlot: currentSlot,
    )) {
      return;
    }

    final workspace = context.read<WorkspaceCubit>();
    if (currentSlot != nextSlot) {
      workspace.moveItem(
          widget.pageIndex, currentSlot, widget.pageIndex, nextSlot);
    }
    workspace.updateWidgetStackSpan(
      widget.pageIndex,
      nextSlot,
      nextSpanX,
      nextSpanY,
    );
  }
}
