import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../services/drag/drag_controller.dart';
import '../../state/workspace_cubit.dart';
import '../icons/bubble_text_view.dart';

class CellLayoutView extends StatelessWidget {
  final WorkspacePage page;
  final int pageIndex;
  final int columns;
  final int rows;
  final double iconSize;
  final bool showLabels;
  final double labelSize;
  final String iconShape;
  final DragController dragController;
  final Map<String, int> badgeCounts;
  final void Function(AppInfo app) onAppTap;
  final void Function(AppInfo app, int slot) onAppLongPress;

  const CellLayoutView({
    super.key,
    required this.page,
    required this.pageIndex,
    required this.columns,
    required this.rows,
    required this.iconSize,
    required this.showLabels,
    required this.labelSize,
    required this.iconShape,
    required this.dragController,
    required this.badgeCounts,
    required this.onAppTap,
    required this.onAppLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final totalSlots = columns * rows;
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: iconSize / (iconSize + (showLabels ? labelSize + 8 : 0) + 8),
      ),
      itemCount: totalSlots,
      itemBuilder: (context, slot) {
        final content = page.slots[slot];
        return DragTarget<DragPayload>(
          onWillAcceptWithDetails: (details) =>
              details.data.sourcePage != pageIndex || details.data.sourceSlot != slot,
          onAcceptWithDetails: (details) {
            context.read<WorkspaceCubit>().moveItem(
                  details.data.sourcePage,
                  details.data.sourceSlot,
                  pageIndex,
                  slot,
                );
          },
          builder: (context, candidateData, rejectedData) {
            final isHovered = candidateData.isNotEmpty;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: isHovered
                  ? BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    )
                  : null,
              child: _buildSlotContent(context, content, slot),
            );
          },
        );
      },
    );
  }

  Widget _buildSlotContent(BuildContext context, SlotContent? content, int slot) {
    if (content == null || content is EmptySlot) {
      return const SizedBox.shrink();
    }

    if (content is AppSlot) {
      final item = content.item;
      final app = AppInfo(
        id: item.id,
        packageName: item.packageName,
        appComponentName: item.componentName ?? item.packageName,
        title: item.title,
        icon: item.icon,
      );
      final badge = badgeCounts[item.packageName] ?? 0;
      return Center(
        child: Draggable<DragPayload>(
          data: DragPayload(item: item, sourcePage: pageIndex, sourceSlot: slot),
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.85,
              child: Transform.scale(
                scale: 1.15,
                child: BubbleTextView(
                  app: app,
                  iconSize: iconSize,
                  showLabel: false,
                  iconShape: iconShape,
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: BubbleTextView(
              app: app,
              iconSize: iconSize,
              showLabel: showLabels,
              labelSize: labelSize,
              iconShape: iconShape,
              badgeCount: badge,
            ),
          ),
          child: BubbleTextView(
            app: app,
            iconSize: iconSize,
            showLabel: showLabels,
            labelSize: labelSize,
            iconShape: iconShape,
            badgeCount: badge,
            onTap: () => onAppTap(app),
            onLongPress: () => onAppLongPress(app, slot),
          ),
        ),
      );
    }

    if (content is FolderSlot) {
      return Center(
        child: Icon(Icons.folder, size: iconSize, color: Colors.amber.shade300),
      );
    }

    return const SizedBox.shrink();
  }
}
