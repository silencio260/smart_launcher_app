import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:smart_launcher_app/core/models/app_info.dart';

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

  Future<void> prewarm(
    Iterable<AppInfo> apps, {
    required int targetPx,
    int limit = 32,
    int concurrency = 2,
    Duration pauseBetweenDecodes = Duration.zero,
    bool Function()? shouldContinue,
  }) async {
    if (limit <= 0 || concurrency <= 0) return;
    final targets = <AppInfo>[];
    for (final app in apps) {
      if (targets.length >= limit) break;
      if (app.iconPath != null && app.iconPath!.isNotEmpty) continue;
      if (app.icon == null) continue;
      if (peek(app.packageName, targetPx) != null) continue;
      targets.add(app);
    }
    if (targets.isEmpty) return;

    var next = 0;
    final workerCount = concurrency.clamp(1, targets.length);
    Future<void> worker() async {
      while (true) {
        if (shouldContinue?.call() == false) return;
        final index = next;
        if (index >= targets.length) return;
        next++;
        final app = targets[index];
        final bytes = app.icon;
        if (bytes == null) continue;
        try {
          await getOrDecode(app.packageName, bytes, targetPx);
        } catch (_) {
          // Broken app icons should not block warming the rest of the drawer.
        }
        if (pauseBetweenDecodes > Duration.zero) {
          await Future<void>.delayed(pauseBetweenDecodes);
        }
      }
    }

    await Future.wait<void>([
      for (var i = 0; i < workerCount; i++) worker(),
    ]);
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
