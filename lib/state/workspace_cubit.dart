import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/workspace_item_info.dart';
import '../models/folder_info.dart';
import '../models/launcher_widget_info.dart';
import '../models/widget_provider_info.dart';
import '../models/item_info.dart';
import '../widgets/workspace/widget_grid_math.dart';
import '../utils/debug_flags.dart';

sealed class SlotContent {}

class AppSlot extends SlotContent {
  final WorkspaceItemInfo item;
  AppSlot(this.item);
}

class FolderSlot extends SlotContent {
  final String folderId;
  FolderSlot(this.folderId);
}

class WidgetSlot extends SlotContent {
  final LauncherWidgetInfo widget;
  WidgetSlot(this.widget);
}

class WidgetStackSlot extends SlotContent {
  final List<LauncherWidgetInfo> widgets;
  final int spanX;
  final int spanY;
  final int currentIndex;

  WidgetStackSlot(
    this.widgets, {
    this.spanX = 2,
    this.spanY = 1,
    int currentIndex = 0,
  }) : currentIndex = widgets.isEmpty
            ? 0
            : currentIndex.clamp(0, widgets.length - 1).toInt();
}

class EmptySlot extends SlotContent {}

class WorkspacePage {
  final Map<int, SlotContent> slots;
  WorkspacePage(this.slots);
  WorkspacePage copyWith({Map<int, SlotContent>? slots}) =>
      WorkspacePage(slots ?? Map.from(this.slots));
}

class WorkspaceState extends Equatable {
  final List<WorkspacePage> pages;
  final int currentPage;
  final bool isLocked;
  final Map<String, FolderInfo> folders;
  final int clockPage;

  const WorkspaceState({
    this.pages = const [],
    this.currentPage = 0,
    this.isLocked = false,
    this.folders = const {},
    this.clockPage = 0,
  });

  WorkspaceState copyWith({
    List<WorkspacePage>? pages,
    int? currentPage,
    bool? isLocked,
    Map<String, FolderInfo>? folders,
    int? clockPage,
  }) =>
      WorkspaceState(
        pages: pages ?? this.pages,
        currentPage: currentPage ?? this.currentPage,
        isLocked: isLocked ?? this.isLocked,
        folders: folders ?? this.folders,
        clockPage: clockPage ?? this.clockPage,
      );

  @override
  List<Object?> get props => [pages, currentPage, isLocked, folders, clockPage];
}

class WorkspaceCubit extends Cubit<WorkspaceState> {
  static const _key = 'workspace_layout_v1';
  static const defaultClockProviderPackage = 'com.genrevibes.smartlauncher';
  static const defaultClockProviderClass = 'builtin.clock';
  static const defaultClockWidgetId = -1001;
  static const defaultClockMinSpanX = 2;
  static const defaultClockMinSpanY = 1;
  static const defaultClockMaxSpanX = 4;
  static const defaultClockMaxSpanY = 2;

  WorkspaceCubit() : super(const WorkspaceState());

  // saveLayout coalescing: a single drag-with-displacement drop can fire 3+
  // emits per frame; without this each one triggers a synchronous jsonEncode
  // + SharedPreferences.setString platform-channel hop on the UI isolate.
  Timer? _saveDebounce;
  bool _savePending = false;
  static const _saveDelay = Duration(milliseconds: 300);

  @override
  Future<void> close() async {
    _saveDebounce?.cancel();
    if (_savePending) {
      await _writeLayout(state);
      _savePending = false;
    }
    return super.close();
  }

  Future<void> loadLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) {
      emit(state.copyWith(pages: [_pageWithDefaultClock()]));
      return;
    }
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      emit(_withDefaultClock(_deserialize(data)));
    } catch (_) {
      emit(state.copyWith(pages: [_pageWithDefaultClock()]));
    }
  }

  // Public entry point used by ~30 emit sites. Coalesces back-to-back writes
  // during drag bursts into a single disk write 300 ms after the last call.
  Future<void> saveLayout() async {
    _savePending = true;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDelay, () async {
      _saveDebounce = null;
      if (!_savePending) return;
      _savePending = false;
      await _writeLayout(state);
    });
  }

  Future<void> _writeLayout(WorkspaceState s) async {
    final map = _serialize(s);
    // jsonEncode of a fully-populated workspace (multiple pages, folders,
    // dozens of widgets) is single-digit ms but adds up across emit storms.
    // compute() ships it to a background isolate; SharedPreferences.setString
    // still has to run on the main isolate but only sees a finished string.
    final encoded =
        await compute<Map<String, dynamic>, String>(jsonEncode, map);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, encoded);
  }

  void setCurrentPage(int page) {
    final maxPage = state.pages.isEmpty ? 0 : state.pages.length - 1;
    emit(state.copyWith(currentPage: page.clamp(0, maxPage)));
  }

  void setClockPage(int page) {
    emit(state.copyWith(clockPage: page.clamp(0, state.pages.length - 1)));
    saveLayout();
  }

  void addPage() {
    final pages = List<WorkspacePage>.from(state.pages)..add(WorkspacePage({}));
    emit(state.copyWith(pages: pages));
    saveLayout();
  }

  WorkspacePage _emptyPage() => WorkspacePage({});

  LauncherWidgetInfo _defaultClockWidget() => LauncherWidgetInfo(
        id: defaultClockWidgetId,
        appWidgetId: defaultClockWidgetId,
        providerPackage: defaultClockProviderPackage,
        providerClass: defaultClockProviderClass,
        isCustomWidget: true,
        minResizeWidth: defaultClockMinSpanX * 110,
        minResizeHeight: defaultClockMinSpanY * 110,
        maxResizeWidth: defaultClockMaxSpanX * 110,
        maxResizeHeight: defaultClockMaxSpanY * 110,
        spanX: defaultClockMaxSpanX,
        spanY: defaultClockMaxSpanY,
      );

  bool _isDefaultClockSlot(SlotContent content) {
    return content is WidgetSlot &&
        content.widget.isCustomWidget &&
        content.widget.providerPackage == defaultClockProviderPackage &&
        content.widget.providerClass == defaultClockProviderClass;
  }

  WorkspacePage _pageWithDefaultClock() {
    return WorkspacePage({0: WidgetSlot(_defaultClockWidget())});
  }

  WorkspaceState _withDefaultClock(WorkspaceState loadedState) {
    final pages = loadedState.pages.isEmpty
        ? <WorkspacePage>[_emptyPage()]
        : loadedState.pages;
    final hasClock =
        pages.any((page) => page.slots.values.any(_isDefaultClockSlot));
    if (hasClock) return loadedState.copyWith(pages: pages);

    final pageZeroSlots = Map<int, SlotContent>.from(pages.first.slots);
    final pageZero = WorkspacePage(pageZeroSlots);
    final clock = _defaultClockWidget();
    final slot = findFirstWidgetFit(
      pageZero,
      clock.spanX,
      clock.spanY,
      5,
      6,
    );
    if (slot == null) return loadedState.copyWith(pages: pages);

    pageZeroSlots[slot] = WidgetSlot(clock);
    final updatedPages = List<WorkspacePage>.from(pages)
      ..[0] = WorkspacePage(pageZeroSlots);
    return loadedState.copyWith(pages: updatedPages);
  }

  bool ensureDefaultClockWidget(int columns, int rows) {
    final pages = state.pages.isEmpty
        ? <WorkspacePage>[_emptyPage()]
        : List<WorkspacePage>.from(state.pages);
    final hasClock =
        pages.any((page) => page.slots.values.any(_isDefaultClockSlot));
    if (hasClock) return false;

    final clock = _defaultClockWidget().copyWith(
      spanX: _defaultClockWidget().spanX.clamp(1, columns),
      spanY: _defaultClockWidget().spanY.clamp(1, rows),
    );
    final firstPage =
        WorkspacePage(Map<int, SlotContent>.from(pages.first.slots));
    final slot = findFirstWidgetFit(
      firstPage,
      clock.spanX,
      clock.spanY,
      columns,
      rows,
    );
    if (slot == null) return false;

    final slots = Map<int, SlotContent>.from(firstPage.slots)
      ..[slot] = WidgetSlot(clock);
    pages[0] = WorkspacePage(slots);
    emit(state.copyWith(pages: pages, clockPage: 0));
    saveLayout();
    return true;
  }

  int _firstFreeAppSlotInPage(
    WorkspacePage page,
    int columns,
    int rows, {
    int? ignoreSlot,
  }) {
    return findFirstAppFit(
          page,
          columns,
          rows,
          ignoreSlot: ignoreSlot,
        ) ??
        0;
  }

  void removePage(int index) {
    if (state.pages.length <= 1) return;
    final pages = List<WorkspacePage>.from(state.pages)..removeAt(index);
    emit(state.copyWith(
      pages: pages,
      currentPage: state.currentPage.clamp(0, pages.length - 1),
    ));
    saveLayout();
  }

  void addItem(WorkspaceItemInfo item, int page, int slot) {
    final pages = List<WorkspacePage>.from(state.pages);
    while (pages.length <= page) {
      pages.add(WorkspacePage({}));
    }
    item.screenId = page;
    final slots = Map<int, SlotContent>.from(pages[page].slots);
    slots[slot] = AppSlot(item);
    pages[page] = WorkspacePage(slots);
    emit(state.copyWith(pages: pages));
    saveLayout();
  }

  ({int page, int slot})? findFirstAvailableAppSlot(int columns, int rows) {
    for (int page = 0; page < state.pages.length; page++) {
      final slot = findFirstAppFit(state.pages[page], columns, rows);
      if (slot != null) return (page: page, slot: slot);
    }
    return null;
  }

  ({int page, int slot}) ensureAppPlacement(int columns, int rows) {
    final existing = findFirstAvailableAppSlot(columns, rows);
    if (existing != null) return existing;

    final pages = List<WorkspacePage>.from(state.pages)..add(_emptyPage());
    final targetPage = pages.length - 1;
    emit(state.copyWith(pages: pages));
    saveLayout();
    return (
      page: targetPage,
      slot: _firstFreeAppSlotInPage(pages[targetPage], columns, rows),
    );
  }

  ({int page, int slot})? findFirstAvailableWidgetSlot(
    int spanX,
    int spanY,
    int columns,
    int rows,
  ) {
    for (int page = 0; page < state.pages.length; page++) {
      final slot = findFirstWidgetFit(
        state.pages[page],
        spanX,
        spanY,
        columns,
        rows,
      );
      if (slot != null) return (page: page, slot: slot);
    }
    return null;
  }

  ({int page, int slot}) ensureWidgetPlacement(
    int spanX,
    int spanY,
    int columns,
    int rows,
  ) {
    final existing = findFirstAvailableWidgetSlot(
      spanX,
      spanY,
      columns,
      rows,
    );
    if (existing != null) return existing;

    final pages = List<WorkspacePage>.from(state.pages)..add(_emptyPage());
    final targetPage = pages.length - 1;
    emit(state.copyWith(pages: pages));
    saveLayout();
    return (page: targetPage, slot: 0);
  }

  ({int page, int slot}) addAppToFirstAvailableSlot(
    WorkspaceItemInfo item,
    int columns,
    int rows,
  ) {
    final placement = ensureAppPlacement(columns, rows);
    addItem(item, placement.page, placement.slot);
    return placement;
  }

  ({int page, int slot}) addWidgetToFirstAvailableSlot(
    LauncherWidgetInfo widget,
    int columns,
    int rows,
  ) {
    widgetLog(
      '[WorkspaceWidgetSizing] addWidget request '
      'provider=${widget.providerPackage}/${widget.providerClass} '
      'grid=${columns}x$rows incomingSpan=${widget.spanX}x${widget.spanY} '
      'minSpan=${widget.minSpanX}x${widget.minSpanY} '
      'maxSpan=${widget.maxSpanX}x${widget.maxSpanY} '
      'rawMin=${widget.minWidth}x${widget.minHeight} '
      'rawMinResize=${widget.minResizeWidth}x${widget.minResizeHeight} '
      'rawMaxResize=${widget.maxResizeWidth}x${widget.maxResizeHeight} '
      'resizeMode=${widget.resizeMode}',
    );
    final placeableWidget = widget.copyWith(
      spanX: widget.spanX.clamp(1, columns),
      spanY: widget.spanY.clamp(1, rows),
    );
    widgetLog(
      '[WorkspaceWidgetSizing] addWidget clamped '
      'provider=${widget.providerPackage}/${widget.providerClass} '
      'placeableSpan=${placeableWidget.spanX}x${placeableWidget.spanY}',
    );
    final placement = ensureWidgetPlacement(
      placeableWidget.spanX,
      placeableWidget.spanY,
      columns,
      rows,
    );
    widgetLog(
      '[WorkspaceWidgetSizing] addWidget placement '
      'provider=${widget.providerPackage}/${widget.providerClass} '
      'page=${placement.page} slot=${placement.slot} '
      'span=${placeableWidget.spanX}x${placeableWidget.spanY}',
    );
    addWidget(placeableWidget, placement.page, placement.slot);
    return placement;
  }

  void addWidget(LauncherWidgetInfo widget, int page, int slot) {
    widgetLog(
      '[WorkspaceWidgetSizing] addWidget save '
      'provider=${widget.providerPackage}/${widget.providerClass} '
      'page=$page slot=$slot span=${widget.spanX}x${widget.spanY} '
      'minSpan=${widget.minSpanX}x${widget.minSpanY} '
      'maxSpan=${widget.maxSpanX}x${widget.maxSpanY}',
    );
    final pages = List<WorkspacePage>.from(state.pages);
    while (pages.length <= page) {
      pages.add(WorkspacePage({}));
    }
    widget.screenId = page;
    final slots = Map<int, SlotContent>.from(pages[page].slots);
    slots[slot] = WidgetSlot(widget);
    pages[page] = WorkspacePage(slots);
    emit(state.copyWith(pages: pages));
    saveLayout();
  }

  void removeItem(int page, int slot) {
    final pages = List<WorkspacePage>.from(state.pages);
    if (page < 0 || page >= pages.length) return;
    final slots = Map<int, SlotContent>.from(pages[page].slots);
    slots.remove(slot);
    pages[page] = WorkspacePage(slots);
    emit(state.copyWith(pages: pages));
    saveLayout();
  }

  /// Removes the widget at [index] from a [WidgetStackSlot] at (page, slot).
  /// If only one widget remains, the stack is downgraded to a [WidgetSlot]
  /// unless [collapseSingle] is false for stack-edit flows that should stay
  /// open after removal.
  /// If the stack becomes empty, the slot is cleared entirely.
  void removeWidgetFromStack(
    int page,
    int slot,
    int index, {
    bool collapseSingle = true,
  }) {
    final pages = List<WorkspacePage>.from(state.pages);
    if (page < 0 || page >= pages.length) return;
    final slots = Map<int, SlotContent>.from(pages[page].slots);
    final current = slots[slot];
    if (current is! WidgetStackSlot) return;
    if (index < 0 || index >= current.widgets.length) return;

    final remaining = List<LauncherWidgetInfo>.from(current.widgets)
      ..removeAt(index);
    var nextIndex = current.currentIndex;
    if (index < nextIndex) nextIndex -= 1;
    if (remaining.isNotEmpty && nextIndex >= remaining.length) {
      nextIndex = remaining.length - 1;
    }
    if (nextIndex < 0) nextIndex = 0;

    if (remaining.isEmpty) {
      slots.remove(slot);
    } else if (remaining.length == 1 && collapseSingle) {
      slots[slot] = WidgetSlot(remaining.single);
    } else {
      slots[slot] = WidgetStackSlot(
        remaining,
        spanX: current.spanX,
        spanY: current.spanY,
        currentIndex: nextIndex,
      );
    }
    pages[page] = WorkspacePage(slots);
    emit(state.copyWith(pages: pages));
    saveLayout();
  }

  /// Adds [newWidget] to the slot at (page, slot). If the slot is already a
  /// [WidgetStackSlot], appends to it. If it's a [WidgetSlot], converts it
  /// into a stack containing both widgets. Existing stacks keep their saved
  /// size; the new widget is normalized into that same span before rendering.
  void addWidgetToStackSlot(
    int page,
    int slot,
    LauncherWidgetInfo newWidget,
  ) {
    final pages = List<WorkspacePage>.from(state.pages);
    if (page < 0 || page >= pages.length) return;
    final slots = Map<int, SlotContent>.from(pages[page].slots);
    final current = slots[slot];

    if (current is WidgetStackSlot) {
      final spanX = current.spanX <= 0 ? 1 : current.spanX;
      final spanY = current.spanY <= 0 ? 1 : current.spanY;
      slots[slot] = WidgetStackSlot(
        [
          ...current.widgets,
          newWidget.copyWith(spanX: spanX, spanY: spanY),
        ],
        spanX: spanX,
        spanY: spanY,
        currentIndex: current.widgets.length,
      );
    } else if (current is WidgetSlot) {
      final spanX = current.widget.spanX <= 0 ? 1 : current.widget.spanX;
      final spanY = current.widget.spanY <= 0 ? 1 : current.widget.spanY;
      slots[slot] = WidgetStackSlot(
        [
          current.widget.copyWith(spanX: spanX, spanY: spanY),
          newWidget.copyWith(spanX: spanX, spanY: spanY),
        ],
        spanX: spanX,
        spanY: spanY,
        currentIndex: 1,
      );
    } else {
      slots[slot] = WidgetStackSlot(
        [newWidget],
        spanX: newWidget.spanX <= 0 ? 1 : newWidget.spanX,
        spanY: newWidget.spanY <= 0 ? 1 : newWidget.spanY,
      );
    }
    pages[page] = WorkspacePage(slots);
    emit(state.copyWith(pages: pages));
    saveLayout();
  }

  void moveItem(int fromPage, int fromSlot, int toPage, int toSlot) {
    final pages = List<WorkspacePage>.from(state.pages);
    if (fromPage < 0 || toPage < 0) return;
    if (fromPage >= pages.length || toPage >= pages.length) return;
    final content = pages[fromPage].slots[fromSlot];
    if (content == null) return;

    if (fromPage == toPage) {
      final slots = Map<int, SlotContent>.from(pages[fromPage].slots)
        ..remove(fromSlot)
        ..[toSlot] = content;
      pages[fromPage] = WorkspacePage(slots);
    } else {
      final fromSlots = Map<int, SlotContent>.from(pages[fromPage].slots)
        ..remove(fromSlot);
      final toSlots = Map<int, SlotContent>.from(pages[toPage].slots)
        ..[toSlot] = content;
      pages[fromPage] = WorkspacePage(fromSlots);
      pages[toPage] = WorkspacePage(toSlots);
    }
    emit(state.copyWith(pages: pages));
    saveLayout();
  }

  void normalizeLayout(int columns, int rows) {
    final originalPages = state.pages.isEmpty ? [_emptyPage()] : state.pages;
    final normalizedPages = <WorkspacePage>[];
    final overflowItems = <SlotContent>[];

    for (final page in originalPages) {
      final slots = Map<int, SlotContent>.from(page.slots);
      final normalized = <int, SlotContent>{};
      final widgetAnchors = slots.entries.where((entry) {
        final content = entry.value;
        return content is WidgetSlot || content is WidgetStackSlot;
      }).toList()
        ..sort((a, b) => a.key.compareTo(b.key));

      for (final entry in widgetAnchors) {
        final anchor = entry.key;
        final content = entry.value;
        final canKeep = switch (content) {
          WidgetSlot(:final widget) => canPlaceWidgetAt(
              WorkspacePage(normalized),
              anchor,
              widget.spanX,
              widget.spanY,
              columns,
              rows,
            ),
          WidgetStackSlot(:final spanX, :final spanY) => canPlaceWidgetAt(
              WorkspacePage(normalized),
              anchor,
              spanX,
              spanY,
              columns,
              rows,
            ),
          _ => false,
        };

        if (canKeep) {
          normalized[anchor] = content;
        } else {
          overflowItems.add(content);
        }
      }

      final blockedByWidgets = occupiedWidgetSlots(
        WorkspacePage(normalized),
        columns,
        rows,
      );

      final nonWidgets = slots.entries.where((entry) {
        final content = entry.value;
        return content is! WidgetSlot && content is! WidgetStackSlot;
      }).toList()
        ..sort((a, b) => a.key.compareTo(b.key));

      for (final entry in nonWidgets) {
        final slot = entry.key;
        final content = entry.value;
        if (blockedByWidgets.contains(slot)) {
          overflowItems.add(content);
          continue;
        }
        if (slot >= columns * rows) {
          overflowItems.add(content);
          continue;
        }
        if (!normalized.containsKey(slot)) {
          normalized[slot] = content;
          continue;
        }
        overflowItems.add(content);
      }

      normalizedPages.add(WorkspacePage(normalized));
    }

    if (normalizedPages.isEmpty) {
      normalizedPages.add(_emptyPage());
    }

    for (final content in overflowItems) {
      if (content is WidgetSlot) {
        final placement = _findWidgetPlacementInPages(
          normalizedPages,
          content.widget.spanX,
          content.widget.spanY,
          columns,
          rows,
        );
        final slots =
            Map<int, SlotContent>.from(normalizedPages[placement.page].slots)
              ..[placement.slot] = content;
        normalizedPages[placement.page] = WorkspacePage(slots);
        continue;
      }

      if (content is WidgetStackSlot) {
        final placement = _findWidgetPlacementInPages(
          normalizedPages,
          content.spanX,
          content.spanY,
          columns,
          rows,
        );
        final slots =
            Map<int, SlotContent>.from(normalizedPages[placement.page].slots)
              ..[placement.slot] = content;
        normalizedPages[placement.page] = WorkspacePage(slots);
        continue;
      }

      final placement =
          _findAppPlacementInPages(normalizedPages, columns, rows);
      final slots =
          Map<int, SlotContent>.from(normalizedPages[placement.page].slots)
            ..[placement.slot] = content;
      normalizedPages[placement.page] = WorkspacePage(slots);
    }

    final currentPage = state.currentPage.clamp(0, normalizedPages.length - 1);
    emit(state.copyWith(pages: normalizedPages, currentPage: currentPage));
    saveLayout();
  }

  ({int page, int slot}) _findAppPlacementInPages(
    List<WorkspacePage> pages,
    int columns,
    int rows,
  ) {
    for (int page = 0; page < pages.length; page++) {
      final slot = findFirstAppFit(pages[page], columns, rows);
      if (slot != null) return (page: page, slot: slot);
    }
    pages.add(_emptyPage());
    return (page: pages.length - 1, slot: 0);
  }

  ({int page, int slot}) _findWidgetPlacementInPages(
    List<WorkspacePage> pages,
    int spanX,
    int spanY,
    int columns,
    int rows,
  ) {
    for (int page = 0; page < pages.length; page++) {
      final slot = findFirstWidgetFit(
        pages[page],
        spanX,
        spanY,
        columns,
        rows,
      );
      if (slot != null) return (page: page, slot: slot);
    }
    pages.add(_emptyPage());
    return (page: pages.length - 1, slot: 0);
  }

  bool shiftItemsAlongPath(int page, List<int> path) {
    if (page < 0 || page >= state.pages.length) return false;
    if (path.length < 2) return false;

    final pages = List<WorkspacePage>.from(state.pages);
    final slots = Map<int, SlotContent>.from(pages[page].slots);

    final destination = slots[path.last];
    if (destination != null && destination is! EmptySlot) {
      return false;
    }

    for (int i = path.length - 1; i > 0; i--) {
      final fromSlot = path[i - 1];
      final toSlot = path[i];
      final content = slots[fromSlot];
      if (content == null || content is EmptySlot) {
        slots.remove(toSlot);
      } else {
        slots[toSlot] = content;
      }
    }

    slots.remove(path.first);
    pages[page] = WorkspacePage(slots);
    emit(state.copyWith(pages: pages));
    saveLayout();
    return true;
  }

  bool moveItemWithDisplacement(
    int fromPage,
    int fromSlot,
    int toPage,
    int toSlot,
    List<int> displacementPath,
  ) {
    if (fromPage < 0 || toPage < 0) return false;
    if (displacementPath.length < 2 || displacementPath.first != toSlot) {
      return false;
    }

    final pages = List<WorkspacePage>.from(state.pages);
    if (fromPage >= pages.length || toPage >= pages.length) return false;

    final moving = pages[fromPage].slots[fromSlot];
    if (moving == null || moving is EmptySlot) return false;

    final fromSlots = Map<int, SlotContent>.from(pages[fromPage].slots)
      ..remove(fromSlot);
    final toSlots = fromPage == toPage
        ? fromSlots
        : Map<int, SlotContent>.from(pages[toPage].slots);

    final destination = toSlots[displacementPath.last];
    if (destination != null && destination is! EmptySlot) return false;

    for (int i = displacementPath.length - 1; i > 0; i--) {
      final from = displacementPath[i - 1];
      final to = displacementPath[i];
      final content = toSlots[from];
      if (content == null || content is EmptySlot) {
        toSlots.remove(to);
      } else {
        toSlots[to] = content;
      }
    }

    toSlots[toSlot] = moving;
    if (fromPage == toPage) {
      pages[fromPage] = WorkspacePage(toSlots);
    } else {
      pages[fromPage] = WorkspacePage(fromSlots);
      pages[toPage] = WorkspacePage(toSlots);
    }

    emit(state.copyWith(pages: pages));
    saveLayout();
    return true;
  }

  bool swapItems(int fromPage, int fromSlot, int toPage, int toSlot) {
    if (fromPage < 0 || toPage < 0) return false;

    final pages = List<WorkspacePage>.from(state.pages);
    if (fromPage >= pages.length || toPage >= pages.length) return false;
    if (fromPage == toPage && fromSlot == toSlot) return false;

    final fromContent = pages[fromPage].slots[fromSlot];
    final toContent = pages[toPage].slots[toSlot];
    if (fromContent == null ||
        fromContent is EmptySlot ||
        toContent == null ||
        toContent is EmptySlot) {
      return false;
    }
    if (fromContent is WidgetSlot ||
        fromContent is WidgetStackSlot ||
        toContent is WidgetSlot ||
        toContent is WidgetStackSlot) {
      return false;
    }

    if (fromPage == toPage) {
      final slots = Map<int, SlotContent>.from(pages[fromPage].slots)
        ..[fromSlot] = toContent
        ..[toSlot] = fromContent;
      pages[fromPage] = WorkspacePage(slots);
    } else {
      final fromSlots = Map<int, SlotContent>.from(pages[fromPage].slots)
        ..[fromSlot] = toContent;
      final toSlots = Map<int, SlotContent>.from(pages[toPage].slots)
        ..[toSlot] = fromContent;
      pages[fromPage] = WorkspacePage(fromSlots);
      pages[toPage] = WorkspacePage(toSlots);
    }

    emit(state.copyWith(pages: pages));
    saveLayout();
    return true;
  }

  // Creates a widget stack from two widget slots (or a widget and a stack).
  // [maxSpanY] is the caller-provided cap so stacks can never fill the column
  // (see _stackMaxRowSpan in cell_layout). The cubit doesn't know grid
  // dimensions itself, so the constraint travels in with the call.
  void createWidgetStack(
    int fromPage,
    int fromSlot,
    int toPage,
    int toSlot, {
    required int maxSpanY,
  }) {
    final pages = List<WorkspacePage>.from(state.pages);
    if (fromPage < 0 || fromPage >= pages.length) return;
    if (toPage < 0 || toPage >= pages.length) return;

    final fromContent = pages[fromPage].slots[fromSlot];
    final toContent = pages[toPage].slots[toSlot];

    final List<LauncherWidgetInfo> merged = [];
    if (fromContent is WidgetSlot) merged.add(fromContent.widget);
    if (fromContent is WidgetStackSlot) merged.addAll(fromContent.widgets);
    if (toContent is WidgetSlot) merged.add(toContent.widget);
    if (toContent is WidgetStackSlot) merged.addAll(toContent.widgets);

    if (merged.isEmpty) return;

    final spanX = merged.map((w) => w.spanX).reduce((a, b) => a > b ? a : b);
    final rawSpanY = merged.map((w) => w.spanY).reduce((a, b) => a > b ? a : b);
    final spanY = rawSpanY.clamp(1, math.max(1, maxSpanY)).toInt();

    if (fromPage == toPage) {
      final slots = Map<int, SlotContent>.from(pages[fromPage].slots)
        ..remove(fromSlot)
        ..[toSlot] = WidgetStackSlot(
          merged,
          spanX: spanX,
          spanY: spanY,
          currentIndex: merged.length - 1,
        );
      pages[fromPage] = WorkspacePage(slots);
    } else {
      final fromSlots = Map<int, SlotContent>.from(pages[fromPage].slots)
        ..remove(fromSlot);
      final toSlots = Map<int, SlotContent>.from(pages[toPage].slots)
        ..[toSlot] = WidgetStackSlot(
          merged,
          spanX: spanX,
          spanY: spanY,
          currentIndex: merged.length - 1,
        );
      pages[fromPage] = WorkspacePage(fromSlots);
      pages[toPage] = WorkspacePage(toSlots);
    }

    emit(state.copyWith(pages: pages));
    saveLayout();
  }

  // Creates a folder from two app slots. Folder lands at slotB (the drop target).
  void createFolder(int page, int slotA, int slotB, String title) {
    final pages = List<WorkspacePage>.from(state.pages);
    if (page >= pages.length) return;
    final slots = Map<int, SlotContent>.from(pages[page].slots);
    final contentA = slots[slotA];
    final contentB = slots[slotB];
    if (contentA is! AppSlot || contentB is! AppSlot) return;

    final folderId = 'folder_${DateTime.now().millisecondsSinceEpoch}';
    final folder = FolderInfo(
      id: folderId.hashCode,
      folderTitle: title,
      contents: [contentA.item, contentB.item],
      cellX: slotB % 5,
      cellY: slotB ~/ 5,
      screenId: page,
    );
    final folders = Map<String, FolderInfo>.from(state.folders)
      ..[folderId] = folder;
    slots.remove(slotA);
    slots.remove(slotB);
    slots[slotB] = FolderSlot(folderId);
    pages[page] = WorkspacePage(slots);
    emit(state.copyWith(pages: pages, folders: folders));
    saveLayout();
  }

  void createFolderFromExternal(
      WorkspaceItemInfo newItem, int page, int targetSlot, String title) {
    final pages = List<WorkspacePage>.from(state.pages);
    if (page >= pages.length) return;
    final slots = Map<int, SlotContent>.from(pages[page].slots);
    final existing = slots[targetSlot];
    if (existing is! AppSlot) return;

    final folderId = 'folder_${DateTime.now().millisecondsSinceEpoch}';
    final folder = FolderInfo(
      id: folderId.hashCode,
      folderTitle: title,
      contents: [existing.item, newItem],
      cellX: targetSlot % 5,
      cellY: targetSlot ~/ 5,
      screenId: page,
    );
    final folders = Map<String, FolderInfo>.from(state.folders)
      ..[folderId] = folder;
    slots[targetSlot] = FolderSlot(folderId);
    pages[page] = WorkspacePage(slots);
    emit(state.copyWith(pages: pages, folders: folders));
    saveLayout();
  }

  bool addToFolder(String folderId, WorkspaceItemInfo item) {
    final folders = Map<String, FolderInfo>.from(state.folders);
    final folder = folders[folderId];
    if (folder == null) return false;
    folders[folderId] = FolderInfo(
      id: folder.id,
      folderTitle: folder.folderTitle,
      contents: [...folder.contents, item],
      cellX: folder.cellX,
      cellY: folder.cellY,
      screenId: folder.screenId,
    );
    emit(state.copyWith(folders: folders));
    saveLayout();
    return true;
  }

  bool addItemsToFolder(String folderId, List<WorkspaceItemInfo> items) {
    if (items.isEmpty) return false;
    final folders = Map<String, FolderInfo>.from(state.folders);
    final folder = folders[folderId];
    if (folder == null) return false;
    folders[folderId] = FolderInfo(
      id: folder.id,
      folderTitle: folder.folderTitle,
      contents: [...folder.contents, ...items],
      cellX: folder.cellX,
      cellY: folder.cellY,
      screenId: folder.screenId,
    );
    emit(state.copyWith(folders: folders));
    saveLayout();
    return true;
  }

  String? createFolderForItems(
    List<WorkspaceItemInfo> items,
    int columns,
    int rows, {
    String title = '',
  }) {
    if (items.isEmpty) return null;
    final pages = state.pages.isEmpty
        ? <WorkspacePage>[_emptyPage()]
        : List<WorkspacePage>.from(state.pages);
    final placement = _findAppPlacementInPages(pages, columns, rows);
    final folderId = 'folder_${DateTime.now().millisecondsSinceEpoch}';
    final folder = FolderInfo(
      id: folderId.hashCode,
      folderTitle: title,
      contents: items,
      cellX: placement.slot % columns,
      cellY: placement.slot ~/ columns,
      screenId: placement.page,
    );
    final slots = Map<int, SlotContent>.from(pages[placement.page].slots)
      ..[placement.slot] = FolderSlot(folderId);
    pages[placement.page] = WorkspacePage(slots);
    final folders = Map<String, FolderInfo>.from(state.folders)
      ..[folderId] = folder;
    emit(state.copyWith(pages: pages, folders: folders));
    saveLayout();
    return folderId;
  }

  void renameFolder(String folderId, String title) {
    final folders = Map<String, FolderInfo>.from(state.folders);
    final folder = folders[folderId];
    if (folder == null) return;
    folders[folderId] = FolderInfo(
      id: folder.id,
      folderTitle: title,
      contents: folder.contents,
      cellX: folder.cellX,
      cellY: folder.cellY,
      screenId: folder.screenId,
    );
    emit(state.copyWith(folders: folders));
    saveLayout();
  }

  bool _sameWorkspaceItem(WorkspaceItemInfo a, WorkspaceItemInfo b) {
    final aComponent = a.componentName ?? a.packageName;
    final bComponent = b.componentName ?? b.packageName;
    return a.packageName == b.packageName &&
        aComponent == bComponent &&
        a.user == b.user;
  }

  int _indexOfWorkspaceItem(
    List<WorkspaceItemInfo> items,
    WorkspaceItemInfo target,
  ) =>
      items.indexWhere((item) => _sameWorkspaceItem(item, target));

  void removeFromFolder(String folderId, WorkspaceItemInfo item) {
    final folders = Map<String, FolderInfo>.from(state.folders);
    final folder = folders[folderId];
    if (folder == null) return;
    final contents = List<WorkspaceItemInfo>.from(folder.contents);
    final itemIndex = _indexOfWorkspaceItem(contents, item);
    if (itemIndex == -1) return;
    contents.removeAt(itemIndex);
    folders[folderId] = FolderInfo(
      id: folder.id,
      folderTitle: folder.folderTitle,
      contents: contents,
      cellX: folder.cellX,
      cellY: folder.cellY,
      screenId: folder.screenId,
    );
    emit(state.copyWith(folders: folders));
    saveLayout();
  }

  void reorderFolderItem(
    String folderId,
    WorkspaceItemInfo fromItem,
    WorkspaceItemInfo toItem,
  ) {
    final folders = Map<String, FolderInfo>.from(state.folders);
    final folder = folders[folderId];
    if (folder == null) return;
    final contents = List<WorkspaceItemInfo>.from(folder.contents);
    final fromIndex = _indexOfWorkspaceItem(contents, fromItem);
    final toIndex = _indexOfWorkspaceItem(contents, toItem);
    if (fromIndex == -1 || toIndex == -1) return;
    final item = contents.removeAt(fromIndex);
    contents.insert(toIndex, item);
    folders[folderId] = FolderInfo(
      id: folder.id,
      folderTitle: folder.folderTitle,
      contents: contents,
      cellX: folder.cellX,
      cellY: folder.cellY,
      screenId: folder.screenId,
    );
    emit(state.copyWith(folders: folders));
    saveLayout();
  }

  void tryCollapseFolder(String folderId, int page, int slot) {
    final folder = state.folders[folderId];
    if (folder == null) return;
    if (folder.contents.length > 1) return;

    final pages = List<WorkspacePage>.from(state.pages);
    if (page >= pages.length) return;
    final slots = Map<int, SlotContent>.from(pages[page].slots);
    if (folder.contents.length == 1) {
      slots[slot] = AppSlot(folder.contents.first);
    } else {
      slots.remove(slot);
    }
    pages[page] = WorkspacePage(slots);
    final folders = Map<String, FolderInfo>.from(state.folders)
      ..remove(folderId);
    emit(state.copyWith(pages: pages, folders: folders));
    saveLayout();
  }

  void movePage(int from, int to) {
    if (from == to) return;
    final pages = List<WorkspacePage>.from(state.pages);
    if (from < 0 || from >= pages.length || to < 0 || to >= pages.length) {
      return;
    }
    final page = pages.removeAt(from);
    pages.insert(to, page);
    final cur = state.currentPage == from
        ? to
        : state.currentPage.clamp(0, pages.length - 1);
    emit(state.copyWith(pages: pages, currentPage: cur));
    saveLayout();
  }

  void collapseEmptyPages() {
    if (state.pages.length <= 1) return;
    final nonEmpty = state.pages.where((p) => p.slots.isNotEmpty).toList();
    if (nonEmpty.length == state.pages.length) return;
    final retained = nonEmpty.isEmpty ? [WorkspacePage({})] : nonEmpty;
    final cur = state.currentPage.clamp(0, retained.length - 1);
    emit(state.copyWith(pages: retained, currentPage: cur));
    saveLayout();
  }

  void updateWidgetSpan(int page, int slot, LauncherWidgetInfo updated) {
    final pages = List<WorkspacePage>.from(state.pages);
    if (page >= pages.length) return;
    final slots = Map<int, SlotContent>.from(pages[page].slots);
    slots[slot] = WidgetSlot(updated);
    pages[page] = WorkspacePage(slots);
    emit(state.copyWith(pages: pages));
    saveLayout();
  }

  void updateWidgetStackSpan(int page, int slot, int spanX, int spanY) {
    final pages = List<WorkspacePage>.from(state.pages);
    if (page >= pages.length) return;
    final slots = Map<int, SlotContent>.from(pages[page].slots);
    final current = slots[slot];
    if (current is WidgetStackSlot) {
      slots[slot] = WidgetStackSlot(
        current.widgets,
        spanX: spanX,
        spanY: spanY,
        currentIndex: current.currentIndex,
      );
      pages[page] = WorkspacePage(slots);
      emit(state.copyWith(pages: pages));
      saveLayout();
    }
  }

  void updateWidgetStackIndex(int page, int slot, int index) {
    final pages = List<WorkspacePage>.from(state.pages);
    if (page < 0 || page >= pages.length) return;
    final slots = Map<int, SlotContent>.from(pages[page].slots);
    final current = slots[slot];
    if (current is! WidgetStackSlot || current.widgets.isEmpty) return;
    final nextIndex = index.clamp(0, current.widgets.length - 1).toInt();
    if (nextIndex == current.currentIndex) return;
    slots[slot] = WidgetStackSlot(
      current.widgets,
      spanX: current.spanX,
      spanY: current.spanY,
      currentIndex: nextIndex,
    );
    pages[page] = WorkspacePage(slots);
    emit(state.copyWith(pages: pages));
    saveLayout();
  }

  void refreshWidgetProviderMetadata(
    List<WidgetProviderInfo> providers,
    int columns,
    int rows,
  ) {
    if (providers.isEmpty) return;
    widgetLog(
      '[WorkspaceWidgetSizing] refreshMetadata start '
      'providerCount=${providers.length} grid=${columns}x$rows',
    );
    final byProvider = {
      for (final provider in providers)
        '${provider.packageName}/${provider.providerClass}': provider,
    };
    var changed = false;
    final pages = state.pages.map((page) {
      final slots = Map<int, SlotContent>.from(page.slots);
      slots.updateAll((slot, content) {
        if (content is WidgetSlot) {
          final updated = _refreshWidgetInfo(
            content.widget,
            byProvider,
            columns,
            rows,
          );
          if (!identical(updated, content.widget)) changed = true;
          return WidgetSlot(updated);
        }
        if (content is WidgetStackSlot) {
          var stackChanged = false;
          final widgets = content.widgets.map((widget) {
            final updated = _refreshWidgetInfo(
              widget,
              byProvider,
              columns,
              rows,
            );
            if (!identical(updated, widget)) stackChanged = true;
            return updated;
          }).toList();
          if (!stackChanged) return content;

          final minSpanX = widgets.fold<int>(
            1,
            (value, widget) =>
                value > widget.minSpanX ? value : widget.minSpanX,
          );
          final minSpanY = widgets.fold<int>(
            1,
            (value, widget) =>
                value > widget.minSpanY ? value : widget.minSpanY,
          );
          final maxSpanX = widgets.fold<int>(
            columns,
            (value, widget) =>
                value < widget.maxSpanX ? value : widget.maxSpanX,
          );
          final maxSpanY = widgets.fold<int>(
            rows,
            (value, widget) =>
                value < widget.maxSpanY ? value : widget.maxSpanY,
          );
          changed = true;
          return WidgetStackSlot(
            widgets,
            spanX: content.spanX
                .clamp(minSpanX, maxSpanX < minSpanX ? minSpanX : maxSpanX)
                .toInt(),
            spanY: content.spanY
                .clamp(minSpanY, maxSpanY < minSpanY ? minSpanY : maxSpanY)
                .toInt(),
            currentIndex: content.currentIndex,
          );
        }
        return content;
      });
      return WorkspacePage(slots);
    }).toList();

    if (!changed) {
      widgetLog(
        '[WorkspaceWidgetSizing] refreshMetadata changed=false',
      );
      return;
    }
    widgetLog(
        '[WorkspaceWidgetSizing] refreshMetadata changed=true saving layout');
    emit(state.copyWith(pages: pages));
    saveLayout();
  }

  LauncherWidgetInfo _refreshWidgetInfo(
    LauncherWidgetInfo widget,
    Map<String, WidgetProviderInfo> providers,
    int columns,
    int rows,
  ) {
    if (widget.isCustomWidget) return widget;
    final provider =
        providers['${widget.providerPackage}/${widget.providerClass}'];
    if (provider == null) {
      widgetLog(
        '[WorkspaceWidgetSizing] refreshWidget missingProvider '
        '${widget.providerPackage}/${widget.providerClass} '
        'storedSpan=${widget.spanX}x${widget.spanY}',
      );
      return widget;
    }
    var minSpanX = provider.minSpanX.clamp(1, columns).toInt();
    var minSpanY = provider.minSpanY.clamp(1, rows).toInt();
    // If the provider's minResize is so large it spans the entire grid, but the
    // widget declares itself resizable, treat the floor as 1 — same override
    // applied in CellLayout._minSpanXForWidget / _minSpanYForWidget.
    if (minSpanX >= columns && provider.resizeMode & 1 != 0) minSpanX = 1;
    if (minSpanY >= rows && provider.resizeMode & 2 != 0) minSpanY = 1;
    final maxSpanX = provider.maxSpanX.clamp(minSpanX, columns).toInt();
    final maxSpanY = provider.maxSpanY.clamp(minSpanY, rows).toInt();
    widgetLog(
      '[WorkspaceWidgetSizing] refreshWidget beforeClamp '
      '${provider.packageName}/${provider.providerClass} '
      'storedSpan=${widget.spanX}x${widget.spanY} '
      'storedMinSpan=${widget.minSpanX}x${widget.minSpanY} '
      'providerSpan=${provider.spanX}x${provider.spanY} '
      'providerMin=${provider.minSpanX}x${provider.minSpanY} '
      'effectiveMin=${minSpanX}x$minSpanY '
      'max=${maxSpanX}x$maxSpanY '
      'target=${provider.targetCellWidth}x${provider.targetCellHeight} '
      'rawMin=${provider.minWidth}x${provider.minHeight} '
      'rawMinResize=${provider.minResizeWidth}x${provider.minResizeHeight} '
      'rawMaxResize=${provider.maxResizeWidth}x${provider.maxResizeHeight} '
      'resizeMode=${provider.resizeMode}',
    );
    var spanX = widget.spanX.clamp(minSpanX, maxSpanX).toInt();
    var spanY = widget.spanY.clamp(minSpanY, maxSpanY).toInt();

    final wasAtOldMinX = widget.minSpanX > 0 && widget.spanX == widget.minSpanX;
    final wasAtOldMinY = widget.minSpanY > 0 && widget.spanY == widget.minSpanY;
    if (wasAtOldMinX &&
        provider.targetCellWidth > 0 &&
        provider.spanX < widget.spanX) {
      spanX = provider.spanX.clamp(minSpanX, maxSpanX).toInt();
    }
    if (wasAtOldMinY &&
        provider.targetCellHeight > 0 &&
        provider.spanY < widget.spanY) {
      spanY = provider.spanY.clamp(minSpanY, maxSpanY).toInt();
    }
    widgetLog(
      '[WorkspaceWidgetSizing] refreshWidget afterClamp '
      '${provider.packageName}/${provider.providerClass} '
      'wasAtOldMin=${wasAtOldMinX}x$wasAtOldMinY '
      'finalSpan=${spanX}x$spanY '
      'finalMinSpan=${minSpanX}x$minSpanY '
      'finalMaxSpan=${maxSpanX}x$maxSpanY',
    );

    return widget.copyWith(
      minWidth: provider.minWidth,
      minHeight: provider.minHeight,
      minResizeWidth: provider.minResizeWidth,
      minResizeHeight: provider.minResizeHeight,
      maxResizeWidth: provider.maxResizeWidth,
      maxResizeHeight: provider.maxResizeHeight,
      resizeMode: provider.resizeMode,
      minSpanX: minSpanX,
      minSpanY: minSpanY,
      maxSpanX: maxSpanX,
      maxSpanY: maxSpanY,
      spanX: spanX,
      spanY: spanY,
    );
  }

  Map<String, dynamic> _serialize(WorkspaceState s) => {
        'currentPage': s.currentPage,
        'clockPage': s.clockPage,
        'isLocked': s.isLocked,
        'pages': s.pages
            .map((p) => {
                  'slots': p.slots
                      .map((k, v) => MapEntry(k.toString(), _serializeSlot(v))),
                })
            .toList(),
        'folders': s.folders.map((k, v) => MapEntry(k, {
              'id': v.id,
              'title': v.folderTitle,
              'cellX': v.cellX,
              'cellY': v.cellY,
              'screenId': v.screenId,
              'contents': v.contents
                  .map((i) => {
                        'packageName': i.packageName,
                        'componentName': i.componentName,
                        'title': i.title,
                      })
                  .toList(),
            })),
      };

  Map<String, dynamic> _serializeSlot(SlotContent slot) {
    if (slot is AppSlot) {
      return {
        'type': 'app',
        'packageName': slot.item.packageName,
        'componentName': slot.item.componentName,
        'title': slot.item.title,
      };
    } else if (slot is FolderSlot) {
      return {'type': 'folder', 'folderId': slot.folderId};
    } else if (slot is WidgetSlot) {
      return {
        'type': 'widget',
        'appWidgetId': slot.widget.appWidgetId,
        'providerPackage': slot.widget.providerPackage,
        'providerClass': slot.widget.providerClass,
        'isCustomWidget': slot.widget.isCustomWidget,
        'minWidth': slot.widget.minWidth,
        'minHeight': slot.widget.minHeight,
        'minResizeWidth': slot.widget.minResizeWidth,
        'minResizeHeight': slot.widget.minResizeHeight,
        'maxResizeWidth': slot.widget.maxResizeWidth,
        'maxResizeHeight': slot.widget.maxResizeHeight,
        'resizeMode': slot.widget.resizeMode,
        'minSpanX': slot.widget.minSpanX,
        'minSpanY': slot.widget.minSpanY,
        'maxSpanX': slot.widget.maxSpanX,
        'maxSpanY': slot.widget.maxSpanY,
        'spanX': slot.widget.spanX,
        'spanY': slot.widget.spanY,
      };
    } else if (slot is WidgetStackSlot) {
      return {
        'type': 'widgetStack',
        'spanX': slot.spanX,
        'spanY': slot.spanY,
        'currentIndex': slot.currentIndex,
        'widgets': slot.widgets
            .map((w) => {
                  'appWidgetId': w.appWidgetId,
                  'providerPackage': w.providerPackage,
                  'providerClass': w.providerClass,
                  'isCustomWidget': w.isCustomWidget,
                  'minWidth': w.minWidth,
                  'minHeight': w.minHeight,
                  'minResizeWidth': w.minResizeWidth,
                  'minResizeHeight': w.minResizeHeight,
                  'maxResizeWidth': w.maxResizeWidth,
                  'maxResizeHeight': w.maxResizeHeight,
                  'resizeMode': w.resizeMode,
                  'minSpanX': w.minSpanX,
                  'minSpanY': w.minSpanY,
                  'maxSpanX': w.maxSpanX,
                  'maxSpanY': w.maxSpanY,
                  'spanX': w.spanX,
                  'spanY': w.spanY,
                })
            .toList(),
      };
    }
    return {'type': 'empty'};
  }

  WorkspaceState _deserialize(Map<String, dynamic> data) {
    final pagesList = (data['pages'] as List? ?? []).map((p) {
      final slotMap = (p['slots'] as Map? ?? {}).map((k, v) {
        final slot = _deserializeSlot(v as Map<String, dynamic>);
        return MapEntry(int.parse(k as String), slot);
      });
      return WorkspacePage(slotMap);
    }).toList();

    final foldersMap = <String, FolderInfo>{};
    final rawFolders = data['folders'] as Map? ?? {};
    rawFolders.forEach((k, v) {
      final vMap = v as Map<String, dynamic>;
      final contents = (vMap['contents'] as List? ?? []).map((c) {
        final cMap = c as Map<String, dynamic>;
        return WorkspaceItemInfo(
          id: 0,
          itemType: ItemType.application,
          packageName: cMap['packageName'] as String,
          componentName: cMap['componentName'] as String?,
          title: cMap['title'] as String?,
        );
      }).toList();
      foldersMap[k as String] = FolderInfo(
        id: vMap['id'] as int? ?? 0,
        folderTitle: vMap['title'] as String? ?? 'Folder',
        contents: contents,
        cellX: vMap['cellX'] as int? ?? 0,
        cellY: vMap['cellY'] as int? ?? 0,
        screenId: vMap['screenId'] as int? ?? 0,
      );
    });

    final loadedPages = pagesList.isEmpty ? [WorkspacePage({})] : pagesList;
    final currentPage =
        (data['currentPage'] as int? ?? 0).clamp(0, loadedPages.length - 1);
    return WorkspaceState(
      pages: loadedPages,
      currentPage: currentPage,
      clockPage:
          (data['clockPage'] as int? ?? 0).clamp(0, loadedPages.length - 1),
      isLocked: data['isLocked'] as bool? ?? false,
      folders: foldersMap,
    );
  }

  SlotContent _deserializeSlot(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'folder':
        return FolderSlot(data['folderId'] as String);
      case 'app':
        final item = WorkspaceItemInfo(
          id: 0,
          itemType: ItemType.application,
          packageName: data['packageName'] as String,
          componentName: data['componentName'] as String?,
          title: data['title'] as String?,
        );
        return AppSlot(item);
      case 'widget':
        return WidgetSlot(LauncherWidgetInfo(
          id: data['appWidgetId'] as int? ?? 0,
          appWidgetId: data['appWidgetId'] as int? ?? 0,
          providerPackage: data['providerPackage'] as String? ?? '',
          providerClass: data['providerClass'] as String? ?? '',
          isCustomWidget: data['isCustomWidget'] as bool? ?? false,
          minWidth: data['minWidth'] as int? ?? 0,
          minHeight: data['minHeight'] as int? ?? 0,
          minResizeWidth: data['minResizeWidth'] as int? ?? 0,
          minResizeHeight: data['minResizeHeight'] as int? ?? 0,
          maxResizeWidth: data['maxResizeWidth'] as int? ?? 0,
          maxResizeHeight: data['maxResizeHeight'] as int? ?? 0,
          resizeMode: data['resizeMode'] as int? ?? 3,
          minSpanX: data['minSpanX'] as int? ?? 0,
          minSpanY: data['minSpanY'] as int? ?? 0,
          maxSpanX: data['maxSpanX'] as int? ?? 0,
          maxSpanY: data['maxSpanY'] as int? ?? 0,
          spanX: data['spanX'] as int? ?? 1,
          spanY: data['spanY'] as int? ?? 1,
        ));
      case 'widgetStack':
        final widgets = (data['widgets'] as List? ?? []).map((w) {
          final wMap = w as Map<String, dynamic>;
          return LauncherWidgetInfo(
            id: wMap['appWidgetId'] as int? ?? 0,
            appWidgetId: wMap['appWidgetId'] as int? ?? 0,
            providerPackage: wMap['providerPackage'] as String? ?? '',
            providerClass: wMap['providerClass'] as String? ?? '',
            isCustomWidget: wMap['isCustomWidget'] as bool? ?? false,
            minWidth: wMap['minWidth'] as int? ?? 0,
            minHeight: wMap['minHeight'] as int? ?? 0,
            minResizeWidth: wMap['minResizeWidth'] as int? ?? 0,
            minResizeHeight: wMap['minResizeHeight'] as int? ?? 0,
            maxResizeWidth: wMap['maxResizeWidth'] as int? ?? 0,
            maxResizeHeight: wMap['maxResizeHeight'] as int? ?? 0,
            resizeMode: wMap['resizeMode'] as int? ?? 3,
            minSpanX: wMap['minSpanX'] as int? ?? 0,
            minSpanY: wMap['minSpanY'] as int? ?? 0,
            maxSpanX: wMap['maxSpanX'] as int? ?? 0,
            maxSpanY: wMap['maxSpanY'] as int? ?? 0,
            spanX: wMap['spanX'] as int? ?? 1,
            spanY: wMap['spanY'] as int? ?? 1,
          );
        }).toList();
        return WidgetStackSlot(
          widgets,
          spanX: data['spanX'] as int? ?? 2,
          spanY: data['spanY'] as int? ?? 1,
          currentIndex: data['currentIndex'] as int? ?? 0,
        );
      default:
        return EmptySlot();
    }
  }
}
