import 'package:smart_launcher_app/core/models/launcher_widget_info.dart';
import 'package:smart_launcher_app/features/home/presentation/bloc/workspace_cubit.dart';

/// Matches `_gridGap` in cell_layout.dart — the spacing between cells used when
/// converting pixel sizes to cell counts. Centralized so placement-time span
/// math agrees with render-time span math.
const double kGridGap = 8.0;

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

/// Effective render-time span for a widget on this grid.
///
/// Mirrors the clamp cell_layout applies at render time: the stored span is
/// pulled up to the resolved min (from explicit minSpan, else from
/// minResizeWidth/minWidth ÷ cell size) and down to the resolved max.
/// Placement search MUST use this — otherwise a reserved slot can be smaller
/// than what gets drawn, and the widget bleeds past its cells.
({int spanX, int spanY}) effectiveWidgetSpan({
  required int storedSpanX,
  required int storedSpanY,
  required int minSpanX,
  required int minSpanY,
  required int maxSpanX,
  required int maxSpanY,
  required int minWidth,
  required int minHeight,
  required int minResizeWidth,
  required int minResizeHeight,
  required int maxResizeWidth,
  required int maxResizeHeight,
  required int resizeMode,
  required int gridColumns,
  required int gridRows,
  required double cellWidth,
  required double cellHeight,
  double gridGap = kGridGap,
}) {
  // resizeMode bits match Android's AppWidgetProviderInfo: 1 = horizontal,
  // 2 = vertical. cell_layout uses these to decide whether a fills-the-grid
  // min should fall back to 1.
  final canResizeH = (resizeMode & 1) != 0;
  final canResizeV = (resizeMode & 2) != 0;

  final effMinX = _resolveMinSpan(
    explicitMin: minSpanX,
    sourceSize: minResizeWidth > 0 ? minResizeWidth : minWidth,
    cellSize: cellWidth,
    maxSpan: gridColumns,
    canResize: canResizeH,
    gridGap: gridGap,
  );
  final effMinY = _resolveMinSpan(
    explicitMin: minSpanY,
    sourceSize: minResizeHeight > 0 ? minResizeHeight : minHeight,
    cellSize: cellHeight,
    maxSpan: gridRows,
    canResize: canResizeV,
    gridGap: gridGap,
  );
  final effMaxX = _resolveMaxSpan(
    explicitMax: maxSpanX,
    sourceSize: maxResizeWidth,
    cellSize: cellWidth,
    minSpan: effMinX,
    maxSpan: gridColumns,
    gridGap: gridGap,
  );
  final effMaxY = _resolveMaxSpan(
    explicitMax: maxSpanY,
    sourceSize: maxResizeHeight,
    cellSize: cellHeight,
    minSpan: effMinY,
    maxSpan: gridRows,
    gridGap: gridGap,
  );

  return (
    spanX: storedSpanX.clamp(effMinX, effMaxX).toInt(),
    spanY: storedSpanY.clamp(effMinY, effMaxY).toInt(),
  );
}

/// Convenience wrapper for stored widgets — feeds [effectiveWidgetSpan] from a
/// [LauncherWidgetInfo] instead of raw fields.
({int spanX, int spanY}) effectiveSpanForWidget(
  LauncherWidgetInfo widget, {
  required int gridColumns,
  required int gridRows,
  required double cellWidth,
  required double cellHeight,
  double gridGap = kGridGap,
}) =>
    effectiveWidgetSpan(
      storedSpanX: widget.spanX,
      storedSpanY: widget.spanY,
      minSpanX: widget.minSpanX,
      minSpanY: widget.minSpanY,
      maxSpanX: widget.maxSpanX,
      maxSpanY: widget.maxSpanY,
      minWidth: widget.minWidth,
      minHeight: widget.minHeight,
      minResizeWidth: widget.minResizeWidth,
      minResizeHeight: widget.minResizeHeight,
      maxResizeWidth: widget.maxResizeWidth,
      maxResizeHeight: widget.maxResizeHeight,
      resizeMode: widget.resizeMode,
      gridColumns: gridColumns,
      gridRows: gridRows,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
      gridGap: gridGap,
    );

int _resolveMinSpan({
  required int explicitMin,
  required int sourceSize,
  required double cellSize,
  required int maxSpan,
  required bool canResize,
  required double gridGap,
}) {
  if (explicitMin > 0) {
    final span = explicitMin.clamp(1, maxSpan).toInt();
    // cell_layout's escape hatch: a min that fills the whole axis AND is
    // resizable is almost always bogus provider metadata, so allow shrinking
    // to 1 rather than locking the widget at full size.
    if (span >= maxSpan && canResize) return 1;
    return span;
  }
  if (sourceSize <= 0 || cellSize <= 0) return 1;
  final span = ((sourceSize + gridGap) / (cellSize + gridGap))
      .ceil()
      .clamp(1, maxSpan)
      .toInt();
  if (span >= maxSpan && canResize) return 1;
  return span;
}

int _resolveMaxSpan({
  required int explicitMax,
  required int sourceSize,
  required double cellSize,
  required int minSpan,
  required int maxSpan,
  required double gridGap,
}) {
  if (explicitMax > 0) return explicitMax.clamp(minSpan, maxSpan).toInt();
  if (sourceSize <= 0 || cellSize <= 0) return maxSpan;
  return ((sourceSize + gridGap) / (cellSize + gridGap))
      .ceil()
      .clamp(minSpan, maxSpan)
      .toInt();
}
