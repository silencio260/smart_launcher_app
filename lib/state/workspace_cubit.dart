import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/workspace_item_info.dart';
import '../models/folder_info.dart';
import '../models/launcher_widget_info.dart';
import '../models/item_info.dart';
import '../widgets/workspace/widget_grid_math.dart';

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
  WidgetStackSlot(this.widgets, {this.spanX = 2, this.spanY = 1});
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

  Future<void> saveLayout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_serialize(state)));
  }

  void setCurrentPage(int page) => emit(state.copyWith(currentPage: page));

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
    final placeableWidget = widget.copyWith(
      spanX: widget.spanX.clamp(1, columns),
      spanY: widget.spanY.clamp(1, rows),
    );
    final placement = ensureWidgetPlacement(
      placeableWidget.spanX,
      placeableWidget.spanY,
      columns,
      rows,
    );
    addWidget(placeableWidget, placement.page, placement.slot);
    return placement;
  }

  void addWidget(LauncherWidgetInfo widget, int page, int slot) {
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
  void createWidgetStack(int fromPage, int fromSlot, int toPage, int toSlot) {
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
    final spanY = merged.map((w) => w.spanY).reduce((a, b) => a > b ? a : b);

    if (fromPage == toPage) {
      final slots = Map<int, SlotContent>.from(pages[fromPage].slots)
        ..remove(fromSlot)
        ..[toSlot] = WidgetStackSlot(merged, spanX: spanX, spanY: spanY);
      pages[fromPage] = WorkspacePage(slots);
    } else {
      final fromSlots = Map<int, SlotContent>.from(pages[fromPage].slots)
        ..remove(fromSlot);
      final toSlots = Map<int, SlotContent>.from(pages[toPage].slots)
        ..[toSlot] = WidgetStackSlot(merged, spanX: spanX, spanY: spanY);
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

  void removeFromFolder(String folderId, int itemId) {
    final folders = Map<String, FolderInfo>.from(state.folders);
    final folder = folders[folderId];
    if (folder == null) return;
    folders[folderId] = FolderInfo(
      id: folder.id,
      folderTitle: folder.folderTitle,
      contents: folder.contents.where((i) => i.id != itemId).toList(),
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
      slots[slot] =
          WidgetStackSlot(current.widgets, spanX: spanX, spanY: spanY);
      pages[page] = WorkspacePage(slots);
      emit(state.copyWith(pages: pages));
      saveLayout();
    }
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
        'spanX': slot.widget.spanX,
        'spanY': slot.widget.spanY,
      };
    } else if (slot is WidgetStackSlot) {
      return {
        'type': 'widgetStack',
        'spanX': slot.spanX,
        'spanY': slot.spanY,
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
    return WorkspaceState(
      pages: loadedPages,
      currentPage: data['currentPage'] as int? ?? 0,
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
            spanX: wMap['spanX'] as int? ?? 1,
            spanY: wMap['spanY'] as int? ?? 1,
          );
        }).toList();
        return WidgetStackSlot(
          widgets,
          spanX: data['spanX'] as int? ?? 2,
          spanY: data['spanY'] as int? ?? 1,
        );
      default:
        return EmptySlot();
    }
  }
}
