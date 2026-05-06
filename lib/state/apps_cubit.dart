import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../models/app_info.dart';
import '../services/launcher_service.dart';

class AppsState extends Equatable {
  final List<AppInfo> apps;
  final Map<String, int> badgeCounts;
  final bool loading;

  const AppsState({
    this.apps = const [],
    this.badgeCounts = const {},
    this.loading = false,
  });

  AppsState copyWith({
    List<AppInfo>? apps,
    Map<String, int>? badgeCounts,
    bool? loading,
  }) =>
      AppsState(
        apps: apps ?? this.apps,
        badgeCounts: badgeCounts ?? this.badgeCounts,
        loading: loading ?? this.loading,
      );

  @override
  List<Object?> get props => [apps, badgeCounts, loading];
}

class AppsCubit extends Cubit<AppsState> {
  static const _badgeEvents = EventChannel('com.genrevibes.smartlauncher/notifications/badge_events');
  static const _notificationChannel = MethodChannel('com.genrevibes.smartlauncher/notifications');

  StreamSubscription<dynamic>? _badgeSub;

  AppsCubit() : super(const AppsState());

  void startBadgeListening() {
    _badgeSub ??= _badgeEvents.receiveBroadcastStream().listen(
      (data) {
        if (data is Map) {
          final counts = data.map((k, v) => MapEntry(k.toString(), (v as int?) ?? 0));
          emit(state.copyWith(badgeCounts: counts));
        }
      },
      onError: (_) {},
    );
  }

  Future<void> refreshBadges() async {
    try {
      final raw = await _notificationChannel.invokeMethod<Map>('getBadgeCounts');
      if (raw != null) {
        final counts = raw.map((k, v) => MapEntry(k.toString(), (v as int?) ?? 0));
        emit(state.copyWith(badgeCounts: counts));
      }
    } catch (_) {}
  }

  @override
  Future<void> close() {
    _badgeSub?.cancel();
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
    emit(state.copyWith(badgeCounts: counts));
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
