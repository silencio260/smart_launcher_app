import 'dart:io';
import 'dart:convert';

import 'package:path_provider/path_provider.dart';

import '../models/app_info.dart';

class AppSnapshot {
  final String snapshotKey;
  final List<AppInfo> apps;

  const AppSnapshot({
    required this.snapshotKey,
    required this.apps,
  });
}

class AppSnapshotCache {
  AppSnapshotCache._();
  static final AppSnapshotCache instance = AppSnapshotCache._();

  static const _fileName = 'launcher_app_snapshot_v2.json';

  Future<AppSnapshot?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      final snapshotKey = raw['snapshotKey'] as String?;
      final appsRaw = raw['apps'] as List?;
      if (snapshotKey == null || appsRaw == null) return null;
      final apps = <AppInfo>[];
      for (final item in appsRaw) {
        if (item is! Map) continue;
        final packageName = item['packageName'] as String?;
        final name = item['name'] as String?;
        if (packageName == null || packageName.isEmpty) continue;
        final iconPath = item['iconPath'] as String?;
        if (iconPath == null ||
            iconPath.isEmpty ||
            !await File(iconPath).exists()) {
          return null;
        }
        apps.add(
          AppInfo(
            id: 0,
            packageName: packageName,
            appComponentName: item['componentName'] as String? ?? packageName,
            title: name ?? packageName,
            iconPath: iconPath,
            isHidden: item['isHidden'] as bool? ?? false,
          ),
        );
      }
      if (apps.isEmpty) return null;
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return AppSnapshot(snapshotKey: snapshotKey, apps: apps);
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required String snapshotKey,
    required List<AppInfo> apps,
  }) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      final payload = <String, Object?>{
        'snapshotKey': snapshotKey,
        'apps': [
          for (final app in apps)
            <String, Object?>{
              'packageName': app.packageName,
              'componentName': app.appComponentName,
              'name': app.name,
              'isHidden': app.isHidden,
              'iconPath': app.iconPath,
            },
        ],
      };
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(payload), flush: true);
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    } catch (_) {
      // The snapshot is only a startup accelerator. A failed write just means
      // the next process launch falls back to native discovery.
    }
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }
}
