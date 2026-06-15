import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:smart_launcher_app/core/models/app_info.dart';
import 'package:smart_launcher_app/core/models/launcher_feature.dart';
import 'package:smart_launcher_app/core/models/workspace_item_info.dart';
import 'package:smart_launcher_app/features/apps/data/app_snapshot_cache.dart';
import 'package:smart_launcher_app/features/apps/data/repositories/apps_repo.dart';
import 'package:smart_launcher_app/features/apps/domain/repositories/apps_base_repo.dart';
import 'package:smart_launcher_app/core/icons/decoded_icon_cache.dart';
import 'package:smart_launcher_app/core/analytics/app_events.dart';

class AppInstallEvent {
  final String packageName;
  final String eventType;

  const AppInstallEvent({
    required this.packageName,
    required this.eventType,
  });

  bool get isAdded => eventType == 'added';
  bool get isRemoved => eventType == 'removed';
  // Fired on app updates (REMOVED/ADDED with EXTRA_REPLACING). Intentionally not
  // treated as add/remove so the assistant never mutates layout on a routine update.
  bool get isUpdated => eventType == 'updated';
}

class AppsState extends Equatable {
  final List<AppInfo> apps;
  final bool loading;
  // O(1) package -> AppInfo lookup. Carried across copyWith when the apps
  // reference is unchanged so toggling `loading` doesn't rebuild a map of
  // potentially thousands of entries.
  final Map<String, AppInfo> appsByPackage;
  final Map<String, AppInfo> appsByKey;
  // launcherFeatureId -> AppInfo for internal mini-apps. The App Hider's
  // disguise swaps which activity-alias is enabled, so its launcherKey
  // (component name) changes; the feature id is the only stable handle to
  // "whatever alias is currently enabled."
  final Map<String, AppInfo> appsByFeatureId;

  const AppsState._({
    required this.apps,
    required this.loading,
    required this.appsByPackage,
    required this.appsByKey,
    required this.appsByFeatureId,
  });

  factory AppsState({
    List<AppInfo> apps = const [],
    bool loading = false,
  }) {
    return AppsState._(
      apps: apps,
      loading: loading,
      appsByPackage: {for (final a in apps) a.packageName: a},
      appsByKey: {for (final a in apps) a.launcherKey: a},
      appsByFeatureId: _featureMap(apps),
    );
  }

  static Map<String, AppInfo> _featureMap(List<AppInfo> apps) => {
        for (final a in apps)
          if (a.launcherFeatureId != null) a.launcherFeatureId!: a,
      };

  AppsState copyWith({
    List<AppInfo>? apps,
    bool? loading,
  }) {
    final nextApps = apps ?? this.apps;
    final unchanged = identical(nextApps, this.apps);
    final nextMap = unchanged
        ? appsByPackage
        : {for (final a in nextApps) a.packageName: a};
    final nextKeyMap =
        unchanged ? appsByKey : {for (final a in nextApps) a.launcherKey: a};
    final nextFeatureMap = unchanged ? appsByFeatureId : _featureMap(nextApps);
    return AppsState._(
      apps: nextApps,
      loading: loading ?? this.loading,
      appsByPackage: nextMap,
      appsByKey: nextKeyMap,
      appsByFeatureId: nextFeatureMap,
    );
  }

  /// Best live [AppInfo] for a pinned [item]. Internal-feature items are matched
  /// by feature id first, because a disguise swaps which activity-alias (and so
  /// which launcherKey) is enabled — the stored component key would otherwise
  /// miss and the tile would freeze on its original label/icon.
  AppInfo? resolveItem(WorkspaceItemInfo item) {
    final fid = item.launcherFeatureId;
    if (fid != null) {
      final byFeature = appsByFeatureId[fid];
      if (byFeature != null) return byFeature;
    }
    return appsByKey[item.launcherKey] ?? appsByPackage[item.packageName];
  }

  /// Best live [AppInfo] for a stored dock reference (a launcherKey string).
  /// Maps a feature's stored component back to its feature id so a disguised
  /// App Hider resolves to the currently-enabled alias.
  AppInfo? resolveRef(String ref) {
    final fid = LauncherFeatureCatalog.idForComponent(ref);
    if (fid != null) {
      final byFeature = appsByFeatureId[fid];
      if (byFeature != null) return byFeature;
    }
    return appsByKey[ref] ?? appsByPackage[ref];
  }

  @override
  List<Object?> get props => [apps, loading];
}

// Per-package badge notifier store. Each badge update only notifies the
// ValueNotifier for packages whose count actually changed, so a single
// app emitting a notification rebuilds exactly one tile instead of
// fanning out to every tile, dock slot, and folder grid on screen.
class BadgeStore {
  final Map<String, ValueNotifier<int>> _byPackage = {};
  Map<String, int> _snapshot = const {};

  ValueListenable<int> listenable(String packageName) {
    return _byPackage.putIfAbsent(
      packageName,
      () => ValueNotifier<int>(_snapshot[packageName] ?? 0),
    );
  }

  int get(String packageName) => _snapshot[packageName] ?? 0;

  Map<String, int> get snapshot => _snapshot;

  void update(Map<String, int> next) {
    final prev = _snapshot;
    if (_mapsEqual(prev, next)) return;
    _snapshot = next;
    final keys = <String>{...prev.keys, ...next.keys};
    for (final k in keys) {
      final n = next[k] ?? 0;
      if ((prev[k] ?? 0) == n) continue;
      final notifier = _byPackage[k];
      if (notifier != null && notifier.value != n) notifier.value = n;
    }
  }

  static bool _mapsEqual(Map<String, int> a, Map<String, int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  void dispose() {
    for (final n in _byPackage.values) {
      n.dispose();
    }
    _byPackage.clear();
  }
}

class AppsCubit extends Cubit<AppsState> {
  static const _badgeEvents =
      EventChannel('com.genrevibes.smartlauncher/notifications/badge_events');
  static const _appInstallEvents =
      EventChannel('com.genrevibes.smartlauncher/app_installs');
  static const _notificationChannel =
      MethodChannel('com.genrevibes.smartlauncher/notifications');

  StreamSubscription<dynamic>? _badgeSub;
  StreamSubscription<dynamic>? _appInstallSub;
  final StreamController<AppInstallEvent> _installEventsController =
      StreamController<AppInstallEvent>.broadcast();
  Timer? _installReloadDebounce;
  Map<String, int>? _pendingBadges;
  bool _badgeFlushScheduled = false;
  bool _badgesEnabled = true;
  final Set<String> _pendingIconEvictions = <String>{};
  String? _snapshotKey;
  bool _loadedSnapshot = false;
  bool _drawerActive = false;
  bool get drawerActive => _drawerActive;
  List<AppInfo>? _pendingApps;
  String? _pendingSnapshotKey;

  // Per-tile badge subscribers attach to this store instead of going
  // through AppsCubit's Bloc state, so badge emits don't re-run every
  // BlocSelector on every workspace/dock/folder tile.
  final BadgeStore badges = BadgeStore();

  final AppsBaseRepo _repo;

  AppsCubit({AppsBaseRepo? repo})
      : _repo = repo ?? const AppsRepo(),
        super(AppsState());

  Stream<AppInstallEvent> get installEvents => _installEventsController.stream;

  // Toggles whether notification badges are shown. When turned off we clear
  // every tile's count (so dots disappear immediately) and stop applying
  // native pushes; turning it back on pulls a fresh snapshot.
  void setBadgesEnabled(bool enabled) {
    if (_badgesEnabled == enabled) return;
    _badgesEnabled = enabled;
    if (!enabled) {
      _pendingBadges = null;
      badges.update(const {});
    } else {
      refreshBadges();
    }
  }

  // Opens the system "Notification access" settings screen so the user can
  // grant access to our NotificationListenerService.
  Future<void> requestNotificationAccess() async {
    try {
      await _notificationChannel.invokeMethod('requestNotificationAccess');
    } catch (_) {}
  }

  // Whether the user has granted notification-listener access to this app.
  Future<bool> isNotificationAccessGranted() async {
    try {
      return await _notificationChannel
              .invokeMethod<bool>('isNotificationAccessGranted') ??
          false;
    } catch (_) {
      return false;
    }
  }

  void startBadgeListening() {
    _badgeSub ??= _badgeEvents.receiveBroadcastStream().listen(
      (data) {
        if (!_badgesEnabled) return;
        if (data is! Map) return;
        // Native sends a full snapshot on every notification change. During
        // a burst (e.g. a chat thread emitting many posts) we'd otherwise
        // run BadgeStore.update once per delivery on the UI thread and
        // starve the frame scheduler. Coalesce to one update per frame.
        _pendingBadges =
            data.map((k, v) => MapEntry(k.toString(), (v as int?) ?? 0));
        _scheduleBadgeFlush();
      },
      onError: (_) {},
    );
  }

  void _scheduleBadgeFlush() {
    if (_badgeFlushScheduled) return;
    _badgeFlushScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _badgeFlushScheduled = false;
      final next = _pendingBadges;
      if (next == null) return;
      _pendingBadges = null;
      badges.update(next);
    });
  }

  void startAppInstallListening() {
    _appInstallSub ??= _appInstallEvents.receiveBroadcastStream().listen(
      (data) {
        if (data is Map) {
          final pkg = data['packageName']?.toString();
          if (pkg != null && pkg.isNotEmpty) {
            _pendingIconEvictions.add(pkg);
            final eventType = data['eventType']?.toString() ?? 'changed';
            AppAnalytics.event(
              'app_install_event',
              params: {
                'event_type': eventType,
                'source': 'package_broadcast',
              },
            );
            if (eventType == 'removed') {
              AppAnalytics.event(
                'installed_app_removed',
                params: {'source': 'package_broadcast'},
              );
            }
            _installEventsController.add(
              AppInstallEvent(packageName: pkg, eventType: eventType),
            );
          }
        }
        // Coalesce bursts (e.g. Play Store post-boot update flurry) into a
        // single reload + a single eviction sweep. Each broadcast otherwise
        // triggers icon eviction and a full PackageManager enumeration on
        // the UI thread, which surfaces as scroll jank for the first few
        // seconds after a fresh restart.
        _installReloadDebounce?.cancel();
        _installReloadDebounce = Timer(const Duration(milliseconds: 400), () {
          _installReloadDebounce = null;
          if (_pendingIconEvictions.isNotEmpty) {
            for (final pkg in _pendingIconEvictions) {
              DecodedIconCache.instance.evict(pkg);
            }
            _pendingIconEvictions.clear();
          }
          loadApps(forceFull: true);
        });
      },
      onError: (_) {},
    );
  }

  Future<void> refreshBadges() async {
    if (!_badgesEnabled) return;
    try {
      final raw =
          await _notificationChannel.invokeMethod<Map>('getBadgeCounts');
      if (raw != null) {
        badges.update(
            raw.map((k, v) => MapEntry(k.toString(), (v as int?) ?? 0)));
      }
    } catch (_) {}
  }

  @override
  Future<void> close() {
    _badgeSub?.cancel();
    _appInstallSub?.cancel();
    _installReloadDebounce?.cancel();
    _installEventsController.close();
    badges.dispose();
    return super.close();
  }

  Future<void> loadCachedThenRefresh() async {
    if (!_loadedSnapshot) {
      _loadedSnapshot = true;
      final snapshot = await AppSnapshotCache.instance.load();
      if (snapshot != null && state.apps.isEmpty) {
        _snapshotKey = snapshot.snapshotKey;
        emit(state.copyWith(
          apps: _withInternalFeatures(snapshot.apps),
          loading: false,
        ));
      }
    }
    await loadApps();
  }

  void setDrawerActive(bool active) {
    if (_drawerActive == active) return;
    _drawerActive = active;
    if (!active) _flushPendingApps();
  }

  Future<void> loadApps({bool forceFull = false}) async {
    if (state.apps.isEmpty) {
      emit(state.copyWith(loading: true));
    }
    try {
      final refreshResult = await _repo.refreshInstalledApps(
        knownSnapshotKey: forceFull ? null : _snapshotKey,
      );
      final refresh = refreshResult.fold((_) => null, (r) => r);
      if (refresh == null) {
        emit(state.copyWith(loading: false));
        return;
      }
      final snapshotKey = refresh.snapshotKey;
      if (!refresh.changed && snapshotKey != null) {
        _snapshotKey = snapshotKey;
        if (state.loading) emit(state.copyWith(loading: false));
        return;
      }

      List<AppInfo> nativeApps;
      if (refresh.apps != null) {
        nativeApps = refresh.apps!;
      } else {
        final fetched = await _repo.getInstalledApps();
        final list = fetched.fold((_) => null, (a) => a);
        if (list == null) {
          emit(state.copyWith(loading: false));
          return;
        }
        nativeApps = list;
      }
      final apps = _withInternalFeatures(nativeApps);
      _snapshotKey = snapshotKey;
      if (_drawerActive && state.apps.isNotEmpty) {
        _pendingApps = apps;
        _pendingSnapshotKey = snapshotKey;
        if (state.loading) emit(state.copyWith(loading: false));
      } else {
        emit(state.copyWith(apps: apps, loading: false));
      }
      if (snapshotKey != null) {
        unawaited(
          AppSnapshotCache.instance.save(
            snapshotKey: snapshotKey,
            apps: nativeApps,
          ),
        );
      }
    } catch (_) {
      emit(state.copyWith(loading: false));
    }
  }

  void _flushPendingApps() {
    final apps = _pendingApps;
    if (apps == null) return;
    _pendingApps = null;
    _snapshotKey = _pendingSnapshotKey;
    _pendingSnapshotKey = null;
    emit(state.copyWith(apps: apps, loading: false));
  }

  List<AppInfo> _withInternalFeatures(List<AppInfo> nativeApps) {
    final featureIds = <String>{};
    final nativeFeatures = <AppInfo>[];
    final filteredNative = <AppInfo>[];
    for (final app in nativeApps) {
      final featureId = LauncherFeatureCatalog.idForComponent(
            app.appComponentName,
          ) ??
          app.launcherFeatureId;
      if (featureId == null) {
        filteredNative.add(app);
        continue;
      }
      nativeFeatures.add(AppInfo(
        id: app.id,
        packageName: app.packageName,
        appComponentName: app.appComponentName,
        title: app.title,
        icon: app.icon,
        iconPath: app.iconPath,
        launcherFeatureId: featureId,
      ));
      featureIds.add(featureId);
    }
    return [
      ...nativeFeatures,
      ...LauncherFeatureCatalog.apps.where(
        (feature) => !featureIds.contains(feature.launcherFeatureId),
      ),
      ...filteredNative,
    ];
  }

  void updateBadges(Map<String, int> counts) {
    badges.update(counts);
  }

  List<AppInfo> searchApps(String query) {
    if (query.isEmpty) return state.apps;
    final q = query.toLowerCase();
    return state.apps.where((a) => a.name.toLowerCase().contains(q)).toList();
  }
}
