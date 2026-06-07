import 'package:smart_launcher_app/core/models/app_info.dart';
import 'package:smart_launcher_app/core/models/folder_info.dart';
import 'package:smart_launcher_app/core/models/item_info.dart';
import 'package:smart_launcher_app/core/models/launcher_feature.dart';
import 'package:smart_launcher_app/core/models/workspace_item_info.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:smart_launcher_app/features/home/presentation/bloc/workspace_cubit.dart';
import 'package:smart_launcher_app/features/apps/data/app_categories.dart';

/// Builds the out-of-box default home layout and writes it into the
/// [WorkspaceCubit] + [SettingsCubit]. Runs once on first install and again
/// whenever the user taps "Reset to default layout".
///
/// Layout produced (4 columns × 5 rows):
///  - Page 1: clock widget (added by [WorkspaceCubit.ensureDefaultClockWidget]),
///            a "Google" folder (YouTube, Chrome, Mail + the rest of the Google
///            suite), a pinned row of YouTube, Chrome, Mail, one calculator and
///            two productivity apps, and the mini-apps (File Locker, App Hider,
///            App Locker) on the bottom row, just above the dock.
///  - Page 2: social-media apps, filling the grid.
///  - Page 3: utility apps, filling the grid.
///  - Page 4: one folder per non-empty category (Social, Google, Utility, …).
///  - Page 5: intentionally empty (a blank scratch page).
///  - Dock:   Dialer, Camera, Clock (our mini Clock mini-app), Message.
class DefaultLayoutSeeder {
  DefaultLayoutSeeder._();

  static const int columns = 4;
  static const int rows = 5;
  static const int dockSize = 4;
  static const String googleFolderTitle = 'Google';

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

    // ---- Page 1: "Google" folder + a pinned row of key apps ----
    // (the clock is added separately, see below).
    final page1Slots = <int, SlotContent>{};
    final googleApps = buckets[AppCategory.google] ?? const <AppInfo>[];

    // Resolve the specific apps we pin on page 1. YouTube/Chrome/Gmail are also
    // front-loaded into the Google folder.
    final youtube = _resolveApp(
        apps, const ['com.google.android.youtube'], const ['youtube']);
    final chrome = _resolveApp(
        apps,
        const ['com.android.chrome', 'com.google.android.apps.chrome'],
        const ['chrome']);
    final gmail =
        _resolveApp(apps, const ['com.google.android.gm'], const ['gmail']);
    final calculator = _resolveApp(
        apps,
        const ['com.google.android.calculator', 'com.android.calculator2'],
        const ['calculator']);

    // Rows 0-1 are reserved for the clock widget; the bottom row is filled with
    // the mini-apps (just above the dock), so the Google folder and the pinned
    // loose icons live in the rows in between.
    final bottomRowStart = columns * (rows - 1);
    var nextPage1Slot = columns * 2;

    var folderSlotIndex = -1;
    if (googleApps.isNotEmpty) {
      final id = newFolderId();
      // Lead the folder with YouTube, Chrome and Mail, then the rest of the
      // Google suite (deduped, original order preserved).
      final ordered = <AppInfo>[];
      final seen = <String>{};
      for (final app in [youtube, chrome, gmail]) {
        if (app != null && seen.add(app.packageName)) ordered.add(app);
      }
      for (final app in googleApps) {
        if (seen.add(app.packageName)) ordered.add(app);
      }
      folders[id] = FolderInfo(
        id: id.hashCode,
        folderTitle: googleFolderTitle,
        contents: ordered.map(_toItem).toList(),
        cellX: 0,
        cellY: 2,
        screenId: 0,
      );
      // Drop the folder just below the top 4×2 area reserved for the clock.
      folderSlotIndex = nextPage1Slot;
      page1Slots[folderSlotIndex] = FolderSlot(id);
      nextPage1Slot++;
    }

    // Pin loose icons on page 1: YouTube, Chrome, Mail, one calculator and two
    // productivity apps, laid out left-to-right just after the Google folder.
    final used = <String>{
      for (final app in [youtube, chrome, gmail, calculator])
        if (app != null) app.packageName,
    };
    final productivity = _resolveProductivityApps(apps, 2, used);
    final pinned = <AppInfo>[
      if (youtube != null) youtube,
      if (chrome != null) chrome,
      if (gmail != null) gmail,
      if (calculator != null) calculator,
      ...productivity,
    ];
    var pinSlot = nextPage1Slot;
    for (final app in pinned) {
      if (pinSlot >= bottomRowStart) break;
      page1Slots[pinSlot] = AppSlot(_toItem(app));
      pinSlot++;
    }

    // ---- Mini-apps on the bottom row, just above the dock ----
    // The Clock mini-app lives in the dock (seeded below), so it's excluded
    // here; the rest are laid out left-to-right on the last row.
    var miniSlot = bottomRowStart;
    for (final feature in LauncherFeatureCatalog.homeFeatures) {
      if (feature.id == LauncherFeatureCatalog.alarmClock.id) continue;
      if (miniSlot >= capacity) break;
      page1Slots[miniSlot] = AppSlot(feature.toWorkspaceItem(screenId: 0));
      miniSlot++;
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

    // ---- Dock: dialer, camera, our Clock mini-app, message ----
    final dock = <String>[
      _resolve(apps, const [
        'com.google.android.dialer',
        'com.android.dialer',
        'com.samsung.android.dialer',
      ], const [
        'dialer',
        'phone'
      ]),
      _resolve(apps, const [
        'com.google.android.GoogleCamera',
        'com.android.camera2',
        'com.android.camera',
        'com.sec.android.app.camera',
      ], const [
        'camera'
      ]),
      // Our own Clock mini-app, not the system clock. Stored as its feature
      // component (a mini-app's launcherKey) so resolveRef maps it back.
      LauncherFeatureCatalog.alarmClock.componentName,
      _resolve(apps, const [
        'com.google.android.apps.messaging',
        'com.android.messaging',
        'com.samsung.android.messaging',
      ], const [
        'messag',
        '.mms',
        '.sms'
      ]),
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
        id: app.launcherKey.hashCode,
        itemType: ItemType.application,
        packageName: app.packageName,
        componentName: app.appComponentName,
        title: app.name,
        icon: app.icon,
        iconPath: app.iconPath,
        launcherFeatureId: app.launcherFeatureId,
      );

  /// Like [_resolve] but returns the matching [AppInfo] (or null), so the
  /// caller can build a workspace slot rather than just a dock package string.
  static AppInfo? _resolveApp(
    List<AppInfo> apps,
    List<String> known,
    List<String> keywords,
  ) {
    for (final pkg in known) {
      for (final app in apps) {
        if (app.packageName == pkg) return app;
      }
    }
    for (final app in apps) {
      final pkg = app.packageName.toLowerCase();
      final title = app.name.toLowerCase();
      for (final kw in keywords) {
        if (pkg.contains(kw) || title.contains(kw)) return app;
      }
    }
    return null;
  }

  /// Picks up to [count] common productivity apps from the installed list,
  /// skipping any package already in [exclude] (which it also extends so the
  /// same app is never pinned twice).
  static List<AppInfo> _resolveProductivityApps(
    List<AppInfo> apps,
    int count,
    Set<String> exclude,
  ) {
    const known = <String>[
      'com.google.android.apps.docs', // Drive
      'com.google.android.keep', // Keep
      'com.google.android.apps.docs.editors.docs',
      'com.google.android.apps.docs.editors.sheets',
      'com.google.android.apps.docs.editors.slides',
      'com.google.android.calendar',
      'com.google.android.apps.tasks',
      'com.microsoft.office.outlook',
      'com.microsoft.office.word',
      'com.microsoft.office.excel',
      'com.microsoft.office.onenote',
      'com.notion.id',
      'com.evernote',
      'com.todoist',
      'com.dropbox.android',
      'com.adobe.reader',
    ];
    final installed = {for (final app in apps) app.packageName: app};
    final result = <AppInfo>[];
    for (final pkg in known) {
      if (result.length >= count) break;
      final app = installed[pkg];
      if (app != null && exclude.add(pkg)) result.add(app);
    }
    return result;
  }

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
