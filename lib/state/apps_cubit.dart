import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../models/app_info.dart';
import '../services/launcher_service.dart';

class AppsState extends Equatable {
  final List<AppInfo> apps;
  final bool loading;
  // O(1) package -> AppInfo lookup. Built once per state instance so the
  // workspace's per-tile BlocSelector doesn't do an O(N) scan of `apps`
  // on every selector invocation.
  final Map<String, AppInfo> appsByPackage;

  AppsState({
    this.apps = const [],
    this.loading = false,
  }) : appsByPackage = {for (final a in apps) a.packageName: a};

  AppsState copyWith({
    List<AppInfo>? apps,
    bool? loading,
  }) =>
      AppsState(
        apps: apps ?? this.apps,
        loading: loading ?? this.loading,
      );

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
  static const _notificationChannel =
      MethodChannel('com.genrevibes.smartlauncher/notifications');

  StreamSubscription<dynamic>? _badgeSub;

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
    badges.dispose();
    return super.close();
  }

  Future<void> loadApps() async {
    emit(state.copyWith(loading: true));
    try {
      final apps = await LauncherService.getInstalledApps();
      emit(state.copyWith(apps: apps, loading: false));
    } catch (_) {
      emit(state.copyWith(loading: false));
    }
  }

  void updateBadges(Map<String, int> counts) {
    badges.update(counts);
  }

  void hideApp(String packageName) {
    final updated = state.apps.map((a) {
      if (a.packageName == packageName) {
        return AppInfo(
          id: a.id,
          packageName: a.packageName,
          appComponentName: a.appComponentName,
          userId: a.userId,
          isDisabled: a.isDisabled,
          isHidden: true,
          icon: a.icon,
          title: a.title,
          rank: a.rank,
        );
      }
      return a;
    }).toList();
    emit(state.copyWith(apps: updated));
  }

  void unhideApp(String packageName) {
    final updated = state.apps.map((a) {
      if (a.packageName == packageName) {
        return AppInfo(
          id: a.id,
          packageName: a.packageName,
          appComponentName: a.appComponentName,
          userId: a.userId,
          isDisabled: a.isDisabled,
          isHidden: false,
          icon: a.icon,
          title: a.title,
          rank: a.rank,
        );
      }
      return a;
    }).toList();
    emit(state.copyWith(apps: updated));
  }

  List<AppInfo> searchApps(String query) {
    if (query.isEmpty) return state.apps.where((a) => !a.isHidden).toList();
    final q = query.toLowerCase();
    return state.apps
        .where((a) => !a.isHidden && (a.name.toLowerCase().contains(q)))
        .toList();
  }
}
