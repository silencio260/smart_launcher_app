import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/workspace_item_info.dart';
import '../../services/drag/drag_controller.dart';
import '../../state/settings_cubit.dart';
import '../../state/workspace_cubit.dart';
import '../workspace/widget_grid_math.dart';

class DragLayer extends StatelessWidget {
  final Widget child;
  final DragController dragController;
  final String iconShape;
  final PageController? pageController;

  const DragLayer({
    super.key,
    required this.child,
    required this.dragController,
    this.iconShape = 'squircle',
    this.pageController,
  });

  @override
  Widget build(BuildContext context) {
    // Pass `child` (the entire workspace subtree) through the `child:` param so
    // it does NOT rebuild on every drag-position notification — the controller
    // notifies on each pointer move, but only the overlay needs that cadence.
    return ListenableBuilder(
      listenable: dragController,
      child: child,
      builder: (context, staticChild) {
        return Stack(
          children: [
            staticChild!,
            if (dragController.isDragging) ...[
              // Subtle background dim while dragging
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ),
              // Left edge zone — hover 600 ms to go to previous page
              Positioned(
                left: 0,
                top: 0,
                bottom: 80,
                child: _EdgePageZone(
                  direction: -1,
                  pageController: pageController,
                  dragController: dragController,
                ),
              ),
              // Right edge zone — hover 600 ms to go to next page (creates page if needed)
              Positioned(
                right: 0,
                top: 0,
                bottom: 80,
                child: _EdgePageZone(
                  direction: 1,
                  pageController: pageController,
                  dragController: dragController,
                ),
              ),
              // Trash zone at the bottom — drop here to remove from home/dock
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _TrashZone(dragController: dragController),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _EdgePageZone extends StatefulWidget {
  final int direction; // -1 = previous, +1 = next
  final PageController? pageController;
  final DragController dragController;

  const _EdgePageZone({
    required this.direction,
    required this.pageController,
    required this.dragController,
  });

  @override
  State<_EdgePageZone> createState() => _EdgePageZoneState();
}

class _EdgePageZoneState extends State<_EdgePageZone> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 600), () {
      final pc = widget.pageController;
      if (pc == null || !pc.hasClients) return;
      if (widget.direction < 0) {
        pc.previousPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut);
      } else {
        final workspaceState = context.read<WorkspaceCubit>().state;
        final settings = context.read<SettingsCubit>().state;
        final payload = widget.dragController.activeDrag;
        final currentPage = pc.page?.round() ?? workspaceState.currentPage;
        final lastPageIndex = workspaceState.pages.length - 1;
        if (currentPage < lastPageIndex) {
          // Navigate to next existing page
          pc.nextPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut);
        } else {
          // On the last page, create a new page only if the dragged item
          // cannot fit anywhere on the current last page.
          final lastPage = workspaceState.pages[lastPageIndex];
          final canFitOnLastPage = payload?.isWidget == true
              ? _canFitWidgetOnPage(
                  workspaceState,
                  payload!,
                  settings.gridColumns,
                  settings.gridRows,
                )
              : findFirstAppFit(
                    lastPage,
                    settings.gridColumns,
                    settings.gridRows,
                    ignoreSlot:
                        payload != null && payload.sourcePage == lastPageIndex
                            ? payload.sourceSlot
                            : null,
                  ) !=
                  null;

          if (!canFitOnLastPage) {
            context.read<WorkspaceCubit>().addPage();
            // After addPage, pages.length increases; navigate to the new last page
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final newLastIndex =
                  context.read<WorkspaceCubit>().state.pages.length - 1;
              pc.animateToPage(newLastIndex,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut);
            });
          }
        }
      }
    });
  }

  bool _canFitWidgetOnPage(
    WorkspaceState workspaceState,
    DragPayload payload,
    int columns,
    int rows,
  ) {
    if (payload.sourcePage < 0 ||
        payload.sourcePage >= workspaceState.pages.length) {
      return false;
    }

    final sourceContent =
        workspaceState.pages[payload.sourcePage].slots[payload.sourceSlot];
    final (spanX, spanY) = switch (sourceContent) {
      WidgetSlot(:final widget) => (widget.spanX, widget.spanY),
      WidgetStackSlot(:final spanX, :final spanY) => (spanX, spanY),
      _ => (1, 1),
    };

    final lastPage = workspaceState.pages.last;
    return findFirstWidgetFit(
          lastPage,
          spanX,
          spanY,
          columns,
          rows,
          ignoreAnchorSlot:
              payload.sourcePage == workspaceState.pages.length - 1
                  ? payload.sourceSlot
                  : null,
        ) !=
        null;
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<DragPayload>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (_) {}, // edge zone is not a real drop target
      builder: (_, candidateData, __) {
        final isHovered = candidateData.isNotEmpty;
        if (isHovered && _timer == null) _startTimer();
        if (!isHovered) _cancelTimer();
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 60,
          decoration: isHovered
              ? BoxDecoration(
                  gradient: LinearGradient(
                    begin: widget.direction > 0
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    end: widget.direction > 0
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.25),
                      Colors.transparent,
                    ],
                  ),
                )
              : null,
          child: isHovered
              ? Center(
                  child: Icon(
                    widget.direction > 0
                        ? Icons.chevron_right
                        : Icons.chevron_left,
                    color: Colors.white.withValues(alpha: 0.8),
                    size: 32,
                  ),
                )
              : null,
        );
      },
    );
  }
}

class _TrashZone extends StatelessWidget {
  final DragController dragController;

  const _TrashZone({required this.dragController});

  @override
  Widget build(BuildContext context) {
    return DragTarget<DragPayload>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final payload = details.data;
        // Drawer drags cannot be trashed (nothing to remove from drawer)
        if (payload.sourcePage == -3) {
          dragController.cancelDrag();
          return;
        }
        final workspace = context.read<WorkspaceCubit>();
        if (payload.folderId != null) {
          // Remove from folder (drag-out → trash)
          final item = payload.item;
          if (item is WorkspaceItemInfo) {
            workspace.removeFromFolder(payload.folderId!, item);
            final remaining =
                workspace.state.folders[payload.folderId!]?.contents.length ??
                    0;
            if (remaining <= 1) {
              workspace.tryCollapseFolder(
                  payload.folderId!, payload.folderPage, payload.folderSlot);
            }
          }
          workspace.collapseEmptyPages();
          payload.onFolderDropCompleted?.call();
        } else if (payload.sourcePage >= 0) {
          // Remove from workspace
          workspace.removeItem(payload.sourcePage, payload.sourceSlot);
          workspace.collapseEmptyPages();
        } else if (payload.sourcePage == -1) {
          // Remove from dock
          final s = context.read<SettingsCubit>().state;
          final packages = List<String>.from(s.dockPackages);
          if (payload.sourceSlot < packages.length) {
            packages[payload.sourceSlot] = '';
          }
          context
              .read<SettingsCubit>()
              .update(s.copyWith(dockPackages: packages));
        }
        dragController.cancelDrag();
      },
      builder: (_, candidateData, __) {
        final isHovered = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: isHovered ? 90 : 70,
          decoration: BoxDecoration(
            color: isHovered
                ? Colors.red.withValues(alpha: 0.75)
                : Colors.black.withValues(alpha: 0.55),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isHovered ? Icons.delete_forever : Icons.delete_outline,
                  color: Colors.white,
                  size: isHovered ? 32 : 26,
                ),
                const SizedBox(height: 2),
                Text(
                  'Remove',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: isHovered ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
