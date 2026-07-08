import 'package:flutter/material.dart';
import 'package:smart_launcher_app/core/models/item_info.dart';

class DragPayload {
  final ItemInfo item;
  final int sourcePage;
  final int sourceSlot;
  // Non-null when the drag originated from inside a folder
  final String? folderId;
  final int folderPage;
  final int folderSlot;
  final VoidCallback? onFolderDropCompleted;

  const DragPayload({
    required this.item,
    required this.sourcePage,
    required this.sourceSlot,
    this.folderId,
    this.folderPage = -1,
    this.folderSlot = -1,
    this.onFolderDropCompleted,
  });

  bool get isWidget => item.itemType == ItemType.appWidget;
}

typedef DisplacementRevertCallback = void Function(
    List<({int page, int fromSlot, int toSlot})> displacements);

abstract class DropTarget {
  bool hitTest(Offset position);
  void onDragEnter(DragPayload payload);
  void onDragExit();
  void onDrop(DragPayload payload, Offset position);
}

class DragController extends ChangeNotifier {
  DragPayload? _activeDrag;
  Offset _dragPosition = Offset.zero;
  DropTarget? _currentTarget;
  final List<DropTarget> _dropTargets = [];

  // Tracks apps displaced during a widget drag so they can be reverted on cancel
  final List<({int page, int fromSlot, int toSlot})> _displacements = [];
  bool _displacementsCommitted = false;

  // Called when drag is cancelled with uncommitted displacements
  DisplacementRevertCallback? onRevertDisplacements;

  DragPayload? get activeDrag => _activeDrag;
  Offset get dragPosition => _dragPosition;
  bool get isDragging => _activeDrag != null;

  void addDropTarget(DropTarget target) => _dropTargets.add(target);
  void removeDropTarget(DropTarget target) => _dropTargets.remove(target);

  void startDrag(
      ItemInfo item, int sourcePage, int sourceSlot, Offset startPos) {
    _activeDrag =
        DragPayload(item: item, sourcePage: sourcePage, sourceSlot: sourceSlot);
    _dragPosition = startPos;
    notifyListeners();
  }

  void startDragPayload(DragPayload payload, Offset startPos) {
    _activeDrag = payload;
    _dragPosition = startPos;
    notifyListeners();
  }

  void updateDragPosition(Offset pos) {
    _dragPosition = pos;
    final hit = _dropTargets.where((t) => t.hitTest(pos)).firstOrNull;
    if (hit != _currentTarget) {
      _currentTarget?.onDragExit();
      _currentTarget = hit;
      if (_activeDrag != null) hit?.onDragEnter(_activeDrag!);
    }
    notifyListeners();
  }

  void onDrop(Offset pos) {
    final payload = _activeDrag;
    if (payload == null) return;
    _currentTarget?.onDrop(payload, pos);
    _reset();
  }

  // Records that an app was displaced to make room for a widget drag.
  void recordDisplacement(int page, int fromSlot, int toSlot) {
    _displacements.add((page: page, fromSlot: fromSlot, toSlot: toSlot));
  }

  // Called on successful drop — displacements are intentional, don't revert.
  void commitDisplacements() {
    _displacementsCommitted = true;
  }

  void cancelDrag() => _reset();

  void _reset() {
    if (!_displacementsCommitted && _displacements.isNotEmpty) {
      onRevertDisplacements?.call(List.from(_displacements));
    }
    _displacements.clear();
    _displacementsCommitted = false;
    _activeDrag = null;
    _currentTarget?.onDragExit();
    _currentTarget = null;
    notifyListeners();
  }
}
