import 'package:flutter/material.dart';
import '../../services/drag/drag_controller.dart';
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
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ),
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
