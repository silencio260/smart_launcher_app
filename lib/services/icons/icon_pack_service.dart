import 'dart:typed_data';
import 'dart:collection';
import 'package:flutter/services.dart';
import '../../models/icon_pack_info.dart';

class IconPackService {
  static const _channel = MethodChannel('com.genrevibes.smartlauncher/apps');
  final _cache = LinkedHashMap<String, Uint8List?>();

  Future<List<IconPackInfo>> getInstalledPacks() async {
    try {
      final result = await _channel.invokeMethod<List>('getInstalledIconPacks');
      return (result ?? [])
          .map((m) => IconPackInfo.fromMap(m as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Uint8List?> getIcon(String packPackage, String packageName) async {
    final key = '$packPackage/$packageName';
    if (_cache.containsKey(key)) return _cache[key];
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('getIconFromPack', {
        'packPackage': packPackage,
        'componentName': packageName,
      });
      _cache[key] = bytes;
      return bytes;
    } catch (_) {
      _cache[key] = null;
      return null;
    }
  }
}
