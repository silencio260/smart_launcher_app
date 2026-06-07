import 'dart:typed_data';

class IconCache {
  static const int _maxSize = 200;
  // Insertion order in Dart's LinkedHashMap doubles as LRU order: we
  // remove-then-reinsert on every read, so the oldest key is always the
  // least-recently-used one.
  final _cache = <String, Uint8List>{};

  Uint8List? get(String packageName) {
    final v = _cache.remove(packageName);
    if (v == null) return null;
    _cache[packageName] = v;
    return v;
  }

  void put(String packageName, Uint8List icon) {
    _cache.remove(packageName);
    if (_cache.length >= _maxSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[packageName] = icon;
  }

  void evict(String packageName) => _cache.remove(packageName);

  void clear() => _cache.clear();
}
