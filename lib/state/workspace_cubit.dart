import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/workspace_item_info.dart';
import '../models/folder_info.dart';
import '../models/launcher_widget_info.dart';
import '../models/item_info.dart';

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

  const WorkspaceState({
    this.pages = const [],
    this.currentPage = 0,
    this.isLocked = false,
    this.folders = const {},
  });

  WorkspaceState copyWith({
    List<WorkspacePage>? pages,
    int? currentPage,
    bool? isLocked,
    Map<String, FolderInfo>? folders,
  }) =>
      WorkspaceState(
        pages: pages ?? this.pages,
        currentPage: currentPage ?? this.currentPage,
        isLocked: isLocked ?? this.isLocked,
        folders: folders ?? this.folders,
      );

  @override
  List<Object?> get props => [pages, currentPage, isLocked, folders];
}

class WorkspaceCubit extends Cubit<WorkspaceState> {
  static const _key = 'workspace_layout_v1';

  WorkspaceCubit() : super(const WorkspaceState());

  Future<void> loadLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) {
      emit(state.copyWith(pages: [WorkspacePage({})]));
      return;
    }
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      emit(_deserialize(data));
    } catch (_) {
      emit(state.copyWith(pages: [WorkspacePage({})]));
    }
  }

  Future<void> saveLayout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_serialize(state)));
  }

  void setCurrentPage(int page) => emit(state.copyWith(currentPage: page));

  void addPage() {
    final pages = List<WorkspacePage>.from(state.pages)..add(WorkspacePage({}));
    emit(state.copyWith(pages: pages));
    saveLayout();
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
    final slots = Map<int, SlotContent>.from(pages[page].slots);
    slots[slot] = AppSlot(item);
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
      // Atomic single-page move — avoids the double-write copy bug
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
    // Folder appears at the target slot (where the user dropped)
    slots[slotB] = FolderSlot(folderId);
    pages[page] = WorkspacePage(slots);
    emit(state.copyWith(pages: pages, folders: folders));
    saveLayout();
  }

  void addToFolder(String folderId, WorkspaceItemInfo item) {
    final folders = Map<String, FolderInfo>.from(state.folders);
    final folder = folders[folderId];
    if (folder == null) return;
    // Avoid duplicates
    if (folder.contents.any((c) => c.packageName == item.packageName)) return;
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

  // Collapses folder to a single app slot (or removes it) when items drop below 2.
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
    if (from < 0 || from >= pages.length || to < 0 || to >= pages.length) return;
    final page = pages.removeAt(from);
    pages.insert(to, page);
    final cur = state.currentPage == from
        ? to
        : state.currentPage.clamp(0, pages.length - 1);
    emit(state.copyWith(pages: pages, currentPage: cur));
    saveLayout();
  }

  // Removes completely empty pages (but always keeps at least one).
  void collapseEmptyPages() {
    if (state.pages.length <= 1) return;
    final nonEmpty =
        state.pages.where((p) => p.slots.isNotEmpty).toList();
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

  Map<String, dynamic> _serialize(WorkspaceState s) => {
        'currentPage': s.currentPage,
        'isLocked': s.isLocked,
        'pages': s.pages
            .map((p) => {
                  'slots': p.slots.map(
                      (k, v) => MapEntry(k.toString(), _serializeSlot(v))),
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

    return WorkspaceState(
      pages: pagesList.isEmpty ? [WorkspacePage({})] : pagesList,
      currentPage: data['currentPage'] as int? ?? 0,
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
      default:
        return EmptySlot();
    }
  }
}
