import '../../state/workspace_cubit.dart';

Iterable<int>? slotsForSpan(
  int anchorSlot,
  int spanX,
  int spanY,
  int columns,
  int rows,
) {
  final anchorCol = anchorSlot % columns;
  final anchorRow = anchorSlot ~/ columns;
  if (anchorCol + spanX > columns || anchorRow + spanY > rows) {
    return null;
  }

  return List<int>.generate(
    spanX * spanY,
    (i) => anchorSlot + (i ~/ spanX) * columns + (i % spanX),
  );
}

Set<int> occupiedWidgetSlots(
  WorkspacePage page,
  int columns,
  int rows, {
  int? ignoreAnchorSlot,
}) {
  final occupied = <int>{};

  for (final entry in page.slots.entries) {
    if (entry.key == ignoreAnchorSlot) continue;

    final content = entry.value;
    final (spanX, spanY) = switch (content) {
      WidgetSlot(:final widget) => (widget.spanX, widget.spanY),
      WidgetStackSlot(:final spanX, :final spanY) => (spanX, spanY),
      _ => (0, 0),
    };

    if (spanX == 0 || spanY == 0) continue;
    final safeSpanX = spanX.clamp(1, columns).toInt();
    final safeSpanY = spanY.clamp(1, rows).toInt();
    final covered =
        slotsForSpan(entry.key, safeSpanX, safeSpanY, columns, rows);
    if (covered != null) occupied.addAll(covered);
  }

  return occupied;
}

bool isSlotCoveredByWidget(
  WorkspacePage page,
  int slot,
  int columns,
  int rows, {
  int? ignoreAnchorSlot,
}) {
  return occupiedWidgetSlots(
    page,
    columns,
    rows,
    ignoreAnchorSlot: ignoreAnchorSlot,
  ).contains(slot);
}

Set<int> currentWidgetCoverage(
  WorkspacePage page,
  int anchorSlot,
  int columns,
  int rows,
) {
  final content = page.slots[anchorSlot];
  final (spanX, spanY) = switch (content) {
    WidgetSlot(:final widget) => (widget.spanX, widget.spanY),
    WidgetStackSlot(:final spanX, :final spanY) => (spanX, spanY),
    _ => (0, 0),
  };

  if (spanX == 0 || spanY == 0) return const <int>{};
  return {...?slotsForSpan(anchorSlot, spanX, spanY, columns, rows)};
}

bool canPlaceWidgetAt(
  WorkspacePage page,
  int anchorSlot,
  int spanX,
  int spanY,
  int columns,
  int rows, {
  int? ignoreAnchorSlot,
}) {
  final covered = slotsForSpan(anchorSlot, spanX, spanY, columns, rows);
  if (covered == null) return false;

  final ignoredCoverage = ignoreAnchorSlot == null
      ? const <int>{}
      : currentWidgetCoverage(page, ignoreAnchorSlot, columns, rows);
  final occupiedByWidgets = occupiedWidgetSlots(
    page,
    columns,
    rows,
    ignoreAnchorSlot: ignoreAnchorSlot,
  );

  for (final slot in covered) {
    if (occupiedByWidgets.contains(slot)) return false;
    if (ignoredCoverage.contains(slot)) continue;

    final content = page.slots[slot];
    if (content != null && content is! EmptySlot) {
      return false;
    }
  }

  return true;
}

bool canPlaceAppAt(
  WorkspacePage page,
  int slot,
  int columns,
  int rows, {
  int? ignoreSlot,
}) {
  if (slot < 0 || slot >= columns * rows) return false;

  if (isSlotCoveredByWidget(
    page,
    slot,
    columns,
    rows,
    ignoreAnchorSlot: ignoreSlot,
  )) {
    return false;
  }

  if (ignoreSlot != null && slot == ignoreSlot) {
    return true;
  }

  final content = page.slots[slot];
  return content == null || content is EmptySlot;
}

int? findFirstAppFit(
  WorkspacePage page,
  int columns,
  int rows, {
  int? ignoreSlot,
}) {
  final totalSlots = columns * rows;
  for (int slot = 0; slot < totalSlots; slot++) {
    if (canPlaceAppAt(
      page,
      slot,
      columns,
      rows,
      ignoreSlot: ignoreSlot,
    )) {
      return slot;
    }
  }
  return null;
}

int? findFirstWidgetFit(
  WorkspacePage page,
  int spanX,
  int spanY,
  int columns,
  int rows, {
  int? ignoreAnchorSlot,
}) {
  final totalSlots = columns * rows;
  for (int slot = 0; slot < totalSlots; slot++) {
    if (canPlaceWidgetAt(
      page,
      slot,
      spanX,
      spanY,
      columns,
      rows,
      ignoreAnchorSlot: ignoreAnchorSlot,
    )) {
      return slot;
    }
  }
  return null;
}
