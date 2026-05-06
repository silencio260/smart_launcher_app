import 'dart:typed_data';

class IconCache {
  static const int _maxSize = 200;
  final _cache = <String, Uint8List>{};

  Uint8List? get(String packageName) => _cache[packageName];

  void put(String packageName, Uint8List icon) {
    if (_cache.length >= _maxSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[packageName] = icon;
  }

  void evict(String packageName) => _cache.remove(packageName);

  void clear() => _cache.clear();
}
