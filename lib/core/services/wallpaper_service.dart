import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'package:smart_launcher_app/core/models/wallpaper_item.dart';

/// Which screen(s) a new phone wallpaper is applied to.
enum WallpaperTarget {
  home,
  lock,
  both;

  bool get includesHome => this != lock;
}

class WallpaperService {
  static const _channel = MethodChannel(
    'com.genrevibes.smartlauncher/wallpaper',
  );
  static const iosTemplateWallpaperAsset =
      'assets/ios_theme/wallpaper/ios_default.webp';
  static String _extension(String fileName) {
    final parts = fileName.toLowerCase().split('.');
    return parts.length < 2 ? '' : parts.last;
  }

  static Future<String> download(WallpaperItem item) async {
    final dir = await _wallpaperDir();
    if (item.isAsset) {
      final ext = _extension(item.assetPath.split('/').last);
      final file = File('${dir.path}/${item.id}.${ext.isEmpty ? 'jpg' : ext}');
      if (await file.exists()) return file.path;
      final data = await rootBundle.load(item.assetPath);
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return file.path;
    }

    final segments = Uri.parse(item.imageUrl).pathSegments;
    final ext = segments.isEmpty ? '' : _extension(segments.last);
    final file = File('${dir.path}/${item.id}.${ext.isEmpty ? 'jpg' : ext}');
    if (await file.exists()) return file.path;

    final client =
        HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final temporaryFile = File('${file.path}.part');
    try {
      final bytes = await (() async {
        final request = await client.getUrl(Uri.parse(item.imageUrl));
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            'Wallpaper download failed: ${response.statusCode}',
          );
        }
        final contentType = response.headers.contentType?.mimeType ?? '';
        if (!contentType.startsWith('image/')) {
          throw const FormatException('The download is not an image');
        }
        return consolidateHttpClientResponseBytes(response);
      })().timeout(const Duration(seconds: 60));
      if (bytes.isEmpty) {
        throw const FormatException('Empty wallpaper download');
      }
      await temporaryFile.writeAsBytes(bytes, flush: true);
      await temporaryFile.rename(file.path);
      return file.path;
    } finally {
      client.close(force: true);
      if (await temporaryFile.exists()) await temporaryFile.delete();
    }
  }

  static Future<bool> applyFile(String path, WallpaperTarget target) async {
    final result = await _channel.invokeMethod<bool>('setWallpaperFromFile', {
      'path': path,
      'target': target.name,
    });
    final applied = result ?? false;
    if (applied && target.includesHome) invalidateSystemWallpaperCache();
    return applied;
  }

  static Future<bool> downloadAndApply(
    WallpaperItem item,
    WallpaperTarget target,
  ) async {
    final path = await download(item);
    return applyFile(path, target);
  }

  static Future<void> openSystemPicker() async {
    await _channel.invokeMethod<void>('changeWallpaper');
    invalidateSystemWallpaperCache();
  }

  /// Returns an app-owned copy of a gallery image, or null when cancelled.
  static Future<String?> pickFromGallery() async {
    return _channel.invokeMethod<String>('pickWallpaperFromGallery');
  }

  static Uint8List? _systemWallpaperCache;
  static bool _systemWallpaperResolved = false;

  /// Cached so opaque surfaces (Spotlight, App Library, Minimal drawer) can show
  /// the wallpaper instantly on repeat opens without a channel round-trip or a
  /// black flash. Returns null when there is no static bitmap (e.g. a live
  /// wallpaper). Call [invalidateSystemWallpaperCache] after the user changes
  /// the wallpaper.
  static Future<Uint8List?> currentSystemWallpaper() async {
    _watchForExternalChanges();
    if (_systemWallpaperResolved) return _systemWallpaperCache;
    final bytes = await _channel.invokeMethod<Uint8List>('getWallpaperBitmap');
    _systemWallpaperCache = bytes;
    _systemWallpaperResolved = true;
    return bytes;
  }

  /// Synchronously returns the cached wallpaper bytes if already resolved, so
  /// callers can seed their first frame without a black flash. Null if not yet
  /// resolved or if there is no static bitmap.
  static Uint8List? get cachedSystemWallpaper =>
      _systemWallpaperResolved ? _systemWallpaperCache : null;

  static bool get isSystemWallpaperResolved => _systemWallpaperResolved;

  static void invalidateSystemWallpaperCache() {
    _systemWallpaperCache = null;
    _systemWallpaperResolved = false;
    systemWallpaperChanges.value++;
  }

  /// Bumped whenever the phone's wallpaper may have changed, so backgrounds
  /// showing it can reload.
  static final systemWallpaperChanges = ValueNotifier<int>(0);

  static AppLifecycleListener? _lifecycle;
  static Future<void>? _changeCheck;

  /// The wallpaper can change outside the launcher (Gallery, system Settings),
  /// so each resume asks native whether its id still matches the cache.
  static void _watchForExternalChanges() {
    _lifecycle ??= AppLifecycleListener(
      onResume: () => _changeCheck ??= _checkForExternalChange().whenComplete(
        () => _changeCheck = null,
      ),
    );
  }

  static Future<void> _checkForExternalChange() async {
    try {
      final changed =
          await _channel.invokeMethod<bool>('checkWallpaperChanged') ?? false;
      if (changed) invalidateSystemWallpaperCache();
    } on PlatformException {
      // Keep the current cache; the next resume retries.
    }
  }

  /// Deletes gallery copies (see [pickFromGallery]) that no setting uses.
  static Future<void> deleteUnusedGalleryCopies(Iterable<String> keep) async {
    final kept = keep
        .where((path) => path.isNotEmpty)
        .map((path) => path.split('/').last)
        .toSet();
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/wallpapers');
      if (!await dir.exists()) return;
      await for (final entry in dir.list()) {
        final name = entry.uri.pathSegments.last;
        if (entry is File &&
            name.startsWith('gallery-') &&
            !kept.contains(name)) {
          await entry.delete();
        }
      }
    } on FileSystemException {
      // Best effort; a leftover copy is retried on the next cleanup.
    }
  }

  static Future<Directory> _wallpaperDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/wallpapers');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
