import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/workspace_item_info.dart';
import '../../services/drag/drag_controller.dart';
import '../../state/settings_cubit.dart';
import '../../state/workspace_cubit.dart';
import '../../utils/debug_flags.dart';

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
              // Right edge zone — hover 600 ms to go to next page. Creates a
              // new empty page when on the last page and that page is not
              // itself empty (prevents stacking empty pages).
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
  static const double _width = 36;
  static const Duration _kTriggerDelay = Duration(milliseconds: 850);

  Timer? _timer;
  // After this zone successfully triggers a page change, stop accepting the
  // drag until the pointer leaves/re-enters the edge band. The edge zone is
  // intentionally not a DragTarget; it should navigate only, never compete
  // with workspace cells for the final drop.
  bool _hasTriggered = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    widget.dragController.addListener(_syncHoverState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncHoverState();
    });
  }

  @override
  void didUpdateWidget(covariant _EdgePageZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dragController == widget.dragController) return;
    oldWidget.dragController.removeListener(_syncHoverState);
    widget.dragController.addListener(_syncHoverState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncHoverState();
    });
  }

  @override
  void dispose() {
    widget.dragController.removeListener(_syncHoverState);
    _timer?.cancel();
    super.dispose();
  }

  void _syncHoverState() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !widget.dragController.isDragging) {
      _setHovered(false);
      return;
    }

    final globalPosition = widget.dragController.dragPosition;
    if (globalPosition == Offset.zero) {
      _setHovered(false);
      return;
    }

    final localPosition = box.globalToLocal(globalPosition);
    _setHovered((Offset.zero & box.size).contains(localPosition));
  }

  void _setHovered(bool hovered) {
    if (!hovered) {
      _cancelTimer();
      if (_isHovered || _hasTriggered) {
        dragDropLog(
          '[WidgetDragDrop][edge ${widget.direction}] hoverExit '
          'pos=${widget.dragController.dragPosition}',
        );
        setState(() {
          _isHovered = false;
          _hasTriggered = false;
        });
      }
      return;
    }

    if (!_isHovered) {
      dragDropLog(
        '[WidgetDragDrop][edge ${widget.direction}] hoverEnter '
        'pos=${widget.dragController.dragPosition}',
      );
      setState(() => _isHovered = true);
    }
    if (!_hasTriggered && _timer == null) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(_kTriggerDelay, () {
      _timer = null;
      final pc = widget.pageController;
      if (pc == null || !pc.hasClients) {
        dragDropLog(
          '[WidgetDragDrop][edge ${widget.direction}] triggerAbort reason=noPageController',
        );
        return;
      }
      bool triggered = false;
      if (widget.direction < 0) {
        dragDropLog(
          '[WidgetDragDrop][edge -1] trigger previous '
          'page=${pc.page?.toStringAsFixed(3)}',
        );
        _refreshDropPreviewAfterNavigation(
          pc.previousPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut),
        );
        triggered = true;
      } else {
        final workspace = context.read<WorkspaceCubit>();
        final workspaceState = workspace.state;
        final currentPage = pc.page?.round() ?? workspaceState.currentPage;
        final lastPageIndex = workspaceState.pages.length - 1;
        dragDropLog(
          '[WidgetDragDrop][edge 1] triggerCheck '
          'page=${pc.page?.toStringAsFixed(3)} current=$currentPage '
          'last=$lastPageIndex lastEmpty=${workspace.isPageEmpty(lastPageIndex)}',
        );
        if (currentPage < lastPageIndex) {
          dragDropLog('[WidgetDragDrop][edge 1] trigger next');
          _refreshDropPreviewAfterNavigation(
            pc.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut),
          );
          triggered = true;
        } else if (!workspace.isPageEmpty(lastPageIndex)) {
          // On the last page. Create a new page only if the current last page
          // actually has content — otherwise the user would be stacking empty
          // pages every time they hovered the edge.
          workspace.addPage();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!pc.hasClients) return;
            final newLastIndex = workspace.state.pages.length - 1;
            dragDropLog(
              '[WidgetDragDrop][edge 1] trigger addPageAndAnimate '
              'newLast=$newLastIndex',
            );
            _refreshDropPreviewAfterNavigation(
              pc.animateToPage(newLastIndex,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut),
            );
          });
          triggered = true;
        } else {
          dragDropLog(
              '[WidgetDragDrop][edge 1] triggerAbort reason=lastPageEmpty');
        }
      }
      if (triggered && mounted) {
        setState(() => _hasTriggered = true);
      }
    });
  }

  void _refreshDropPreviewAfterNavigation(Future<void> navigation) {
    navigation.whenComplete(() {
      if (!mounted || !widget.dragController.isDragging) return;
      final position = widget.dragController.dragPosition;
      if (position == Offset.zero) return;
      dragDropLog(
        '[WidgetDragDrop][edge ${widget.direction}] refreshDropPreview '
        'pos=$position',
      );
      widget.dragController.updateDragPosition(position);
      // Re-arm so a still-hovering pointer can chain into the next page
      // without needing to leave and re-enter the edge band.
      if (_hasTriggered) {
        setState(() => _hasTriggered = false);
        _syncHoverState();
      }
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: _width,
        decoration: _isHovered
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
        child: _isHovered
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
      ),
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
