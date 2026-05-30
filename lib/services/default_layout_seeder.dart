import '../models/app_info.dart';
import '../models/folder_info.dart';
import '../models/item_info.dart';
import '../models/workspace_item_info.dart';
import '../state/settings_cubit.dart';
import '../state/workspace_cubit.dart';
import 'app_categories.dart';

/// Builds the out-of-box default home layout and writes it into the
/// [WorkspaceCubit] + [SettingsCubit]. Runs once on first install and again
/// whenever the user taps "Reset to default layout".
///
/// Layout produced (4 columns × 5 rows):
///  - Page 1: clock widget (added by [WorkspaceCubit.ensureDefaultClockWidget])
///            plus a "google" folder of Chrome + the Google suite.
///  - Page 2: social-media apps, filling the grid.
///  - Page 3: utility apps, filling the grid.
///  - Page 4: one folder per non-empty category (Social, Google, Utility, …).
///  - Page 5: intentionally empty (a blank scratch page).
///  - Dock:   Dialer, Camera, Clock, Message.
class DefaultLayoutSeeder {
  DefaultLayoutSeeder._();

  static const int columns = 4;
  static const int rows = 5;
  static const int dockSize = 4;
  static const String googleFolderTitle = 'google';

  /// Order in which category folders are laid out on page 4.
  static const List<AppCategory> _page4Order = [
    AppCategory.google,
    AppCategory.social,
    AppCategory.communication,
    AppCategory.utility,
    AppCategory.photography,
    AppCategory.music,
    AppCategory.video,
    AppCategory.games,
    AppCategory.finance,
    AppCategory.shopping,
    AppCategory.travel,
    AppCategory.health,
    AppCategory.news,
    AppCategory.productivity,
    AppCategory.tools,
    AppCategory.system,
  ];

  /// Returns true if the layout was seeded (false when there are no apps yet).
  static bool seed({
    required List<AppInfo> apps,
    required WorkspaceCubit workspace,
    required SettingsCubit settings,
  }) {
    if (apps.isEmpty) return false;

    final buckets = categorizeApps(apps);
    final capacity = columns * rows;
    final folders = <String, FolderInfo>{};
    var folderSeq = 0;
    String newFolderId() =>
        'folder_${DateTime.now().millisecondsSinceEpoch}_${folderSeq++}';

    // ---- Page 1: "google" folder (clock is added separately, see below) ----
    final page1Slots = <int, SlotContent>{};
    final googleApps = buckets[AppCategory.google] ?? const <AppInfo>[];
    if (googleApps.isNotEmpty) {
      final id = newFolderId();
      folders[id] = FolderInfo(
        id: id.hashCode,
        folderTitle: googleFolderTitle,
        contents: googleApps.map(_toItem).toList(),
        cellX: 0,
        cellY: 2,
        screenId: 0,
      );
      // Drop the folder just below the top 4×2 area reserved for the clock.
      page1Slots[columns * 2] = FolderSlot(id);
    }

    // ---- Pages 2 & 3: loose apps ----
    final page2 = _appPage(buckets[AppCategory.social] ?? const [], capacity);
    final page3 = _appPage(buckets[AppCategory.utility] ?? const [], capacity);

    // ---- Page 4: one folder per non-empty category ----
    final page4Slots = <int, SlotContent>{};
    var slot = 0;
    for (final category in _page4Order) {
      final catApps = buckets[category];
      if (catApps == null || catApps.isEmpty) continue;
      if (slot >= capacity) break;
      final id = newFolderId();
      folders[id] = FolderInfo(
        id: id.hashCode,
        folderTitle: category.label,
        contents: catApps.map(_toItem).toList(),
        cellX: slot % columns,
        cellY: slot ~/ columns,
        screenId: 3,
      );
      page4Slots[slot] = FolderSlot(id);
      slot++;
    }

    // ---- Page 5: intentionally left empty (a blank scratch page) ----
    final page5 = WorkspacePage(<int, SlotContent>{});

    workspace.seedDefaultLayout(
      pages: [
        WorkspacePage(page1Slots),
        page2,
        page3,
        WorkspacePage(page4Slots),
        page5,
      ],
      folders: folders,
      clockPage: 0,
    );
    // Place the default clock on page 1 (also covers "Reset to default layout",
    // which runs after the home screen's one-shot clock seed has already fired).
    workspace.ensureDefaultClockWidget(columns, rows);

    // ---- Dock: dialer, camera, clock, message ----
    final dock = <String>[
      _resolve(apps, const [
        'com.google.android.dialer',
        'com.android.dialer',
        'com.samsung.android.dialer',
      ], const ['dialer', 'phone']),
      _resolve(apps, const [
        'com.google.android.GoogleCamera',
        'com.android.camera2',
        'com.android.camera',
        'com.sec.android.app.camera',
      ], const ['camera']),
      _resolve(apps, const [
        'com.google.android.deskclock',
        'com.android.deskclock',
        'com.sec.android.app.clockpackage',
      ], const ['clock', 'deskclock']),
      _resolve(apps, const [
        'com.google.android.apps.messaging',
        'com.android.messaging',
        'com.samsung.android.messaging',
      ], const ['messag', '.mms', '.sms']),
    ];

    settings.update(settings.state.copyWith(
      gridColumns: columns,
      gridRows: rows,
      dockSize: dockSize,
      dockPackages: dock,
    ));
    return true;
  }

  static WorkspacePage _appPage(List<AppInfo> apps, int capacity) {
    final slots = <int, SlotContent>{};
    final count = apps.length < capacity ? apps.length : capacity;
    for (var i = 0; i < count; i++) {
      slots[i] = AppSlot(_toItem(apps[i]));
    }
    return WorkspacePage(slots);
  }

  static WorkspaceItemInfo _toItem(AppInfo app) => WorkspaceItemInfo(
        id: app.packageName.hashCode,
        itemType: ItemType.application,
        packageName: app.packageName,
        componentName: app.appComponentName,
        title: app.name,
        icon: app.icon,
        iconPath: app.iconPath,
      );

  /// First installed package matching [known], else the first whose package or
  /// title contains a [keywords] entry, else '' (an empty dock slot).
  static String _resolve(
    List<AppInfo> apps,
    List<String> known,
    List<String> keywords,
  ) {
    final installed = {for (final a in apps) a.packageName};
    for (final pkg in known) {
      if (installed.contains(pkg)) return pkg;
    }
    for (final app in apps) {
      final pkg = app.packageName.toLowerCase();
      final title = app.name.toLowerCase();
      for (final kw in keywords) {
        if (pkg.contains(kw) || title.contains(kw)) return app.packageName;
      }
    }
    return '';
  }
}
