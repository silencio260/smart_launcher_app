import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../models/app_info.dart';
import '../services/app_snapshot_cache.dart';
import '../services/icons/decoded_icon_cache.dart';
import '../services/launcher_service.dart';

class AppsState extends Equatable {
  final List<AppInfo> apps;
  final bool loading;
  // O(1) package -> AppInfo lookup. Carried across copyWith when the apps
  // reference is unchanged so toggling `loading` doesn't rebuild a map of
  // potentially thousands of entries.
  final Map<String, AppInfo> appsByPackage;

  const AppsState._({
    required this.apps,
    required this.loading,
    required this.appsByPackage,
  });

  factory AppsState({
    List<AppInfo> apps = const [],
    bool loading = false,
  }) {
    return AppsState._(
      apps: apps,
      loading: loading,
      appsByPackage: {for (final a in apps) a.packageName: a},
    );
  }

  AppsState copyWith({
    List<AppInfo>? apps,
    bool? loading,
  }) {
    final nextApps = apps ?? this.apps;
    final nextMap = identical(nextApps, this.apps)
        ? appsByPackage
        : {for (final a in nextApps) a.packageName: a};
    return AppsState._(
      apps: nextApps,
      loading: loading ?? this.loading,
      appsByPackage: nextMap,
    );
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
    _snapshot = next;
    final keys = <String>{...prev.keys, ...next.keys};
    for (final k in keys) {
      final n = next[k] ?? 0;
      if ((prev[k] ?? 0) == n) continue;
      final notifier = _byPackage[k];
      if (notifier != null && notifier.value != n) notifier.value = n;
    }
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

  AppsCubit() : super(AppsState());

  void startBadgeListening() {
    _badgeSub ??= _badgeEvents.receiveBroadcastStream().listen(
      (data) {
        if (data is Map) {
          badges.update(
              data.map((k, v) => MapEntry(k.toString(), (v as int?) ?? 0)));
        }
      },
      onError: (_) {},
    );
  }

  void startAppInstallListening() {
    _appInstallSub ??= _appInstallEvents.receiveBroadcastStream().listen(
      (data) {
        if (data is Map) {
          final pkg = data['packageName']?.toString();
          if (pkg != null && pkg.isNotEmpty) {
            DecodedIconCache.instance.evict(pkg);
          }
        }
        loadApps(forceFull: true);
      },
      onError: (_) {},
    );
  }

  Future<void> refreshBadges() async {
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
    badges.dispose();
    return super.close();
  }

  Future<void> loadCachedThenRefresh() async {
    if (!_loadedSnapshot) {
      _loadedSnapshot = true;
      final snapshot = await AppSnapshotCache.instance.load();
      if (snapshot != null && state.apps.isEmpty) {
        _snapshotKey = snapshot.snapshotKey;
        emit(state.copyWith(apps: snapshot.apps, loading: false));
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
      final refresh = await LauncherService.refreshInstalledApps(
        knownSnapshotKey: forceFull ? null : _snapshotKey,
      );
      final snapshotKey = refresh.snapshotKey;
      if (!refresh.changed && snapshotKey != null) {
        _snapshotKey = snapshotKey;
        if (state.loading) emit(state.copyWith(loading: false));
        return;
      }

      final apps = refresh.apps ?? await LauncherService.getInstalledApps();
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
            apps: apps,
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

  void updateBadges(Map<String, int> counts) {
    badges.update(counts);
  }

  List<AppInfo> searchApps(String query) {
    if (query.isEmpty) return state.apps;
    final q = query.toLowerCase();
    return state.apps
        .where((a) => a.name.toLowerCase().contains(q))
        .toList();
  }
}
