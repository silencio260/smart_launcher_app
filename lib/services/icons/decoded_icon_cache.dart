import 'dart:typed_data';
import 'dart:ui' as ui;

/// Process-wide LRU cache of decoded [ui.Image] icons keyed by
/// `package@sizePx`. Decoding happens once per (package, target pixel size);
/// subsequent calls return the same [ui.Image] handle, so RawImage paints
/// without re-decoding or re-uploading to the GPU.
class DecodedIconCache {
  DecodedIconCache._();
  static final DecodedIconCache instance = DecodedIconCache._();

  static const int _maxEntries = 256;

  final Map<String, ui.Image> _ready = <String, ui.Image>{};
  final Map<String, Future<ui.Image>> _pending = <String, Future<ui.Image>>{};

  String _key(String pkg, int targetPx) => '$pkg@$targetPx';

  ui.Image? peek(String pkg, int targetPx) {
    final k = _key(pkg, targetPx);
    final img = _ready.remove(k);
    if (img == null) return null;
    _ready[k] = img;
    return img;
  }

  Future<ui.Image> getOrDecode(
    String pkg,
    Uint8List bytes,
    int targetPx,
  ) {
    final k = _key(pkg, targetPx);
    final ready = _ready.remove(k);
    if (ready != null) {
      _ready[k] = ready;
      return Future.value(ready);
    }
    final pending = _pending[k];
    if (pending != null) return pending;
    final future = _decode(bytes, targetPx).then((img) {
      _pending.remove(k);
      _insert(k, img);
      return img;
    }, onError: (e, s) {
      _pending.remove(k);
      throw e;
    });
    _pending[k] = future;
    return future;
  }

  void _insert(String key, ui.Image img) {
    if (_ready.containsKey(key)) {
      _ready.remove(key)?.dispose();
    }
    _ready[key] = img;
    while (_ready.length > _maxEntries) {
      final firstKey = _ready.keys.first;
      _ready.remove(firstKey)?.dispose();
    }
  }

  Future<ui.Image> _decode(Uint8List bytes, int targetPx) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetPx,
      targetHeight: targetPx,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  void evict(String pkg) {
    final prefix = '$pkg@';
    final keys = _ready.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      _ready.remove(k)?.dispose();
    }
  }

  void clear() {
    for (final img in _ready.values) {
      img.dispose();
    }
    _ready.clear();
    _pending.clear();
  }
}
