import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/drag/drag_controller.dart';
import '../../state/settings_cubit.dart';
import '../../state/workspace_cubit.dart';
import 'drag_view.dart';

class DragLayer extends StatelessWidget {
  final Widget child;
  final DragController dragController;
  final String iconShape;

  const DragLayer({
    super.key,
    required this.child,
    required this.dragController,
    this.iconShape = 'squircle',
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dragController,
      builder: (context, _) {
        return Stack(
          children: [
            child,
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
              // Trash zone at the bottom — drop here to remove from home/dock
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _TrashZone(dragController: dragController),
              ),
              // Floating drag icon follows the pointer
              DragView(
                payload: dragController.activeDrag!,
                position: dragController.dragPosition,
                iconShape: iconShape,
              ),
            ],
          ],
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
        if (payload.sourcePage >= 0) {
          // Remove from workspace
          context
              .read<WorkspaceCubit>()
              .removeItem(payload.sourcePage, payload.sourceSlot);
          context.read<WorkspaceCubit>().collapseEmptyPages();
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
                    fontWeight:
                        isHovered ? FontWeight.bold : FontWeight.normal,
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
