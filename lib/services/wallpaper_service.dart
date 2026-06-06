import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/wallpaper_item.dart';

class WallpaperService {
  static const _channel =
      MethodChannel('com.genrevibes.smartlauncher/wallpaper');
  static const storeUrl =
      'https://raw.githubusercontent.com/code3-dev/code3-dev/refs/heads/main/pc.json';

  static const fallbackUrls = <String>[
    'https://raw.githubusercontent.com/code3-dev/code3-dev/refs/heads/main/data/m1.jpg',
    'https://raw.githubusercontent.com/code3-dev/code3-dev/refs/heads/main/data/m2.jpg',
    'https://raw.githubusercontent.com/code3-dev/code3-dev/refs/heads/main/data/m3.jpg',
    'https://raw.githubusercontent.com/code3-dev/code3-dev/refs/heads/main/data/m4.jpg',
    'https://raw.githubusercontent.com/code3-dev/code3-dev/refs/heads/main/data/m5.jpg',
    'https://raw.githubusercontent.com/code3-dev/code3-dev/refs/heads/main/data/m6.jpg',
    'https://raw.githubusercontent.com/code3-dev/code3-dev/refs/heads/main/data/public.gif',
  ];

  static Future<List<WallpaperItem>> fetchStore() async {
    try {
      final request = await HttpClient().getUrl(Uri.parse(storeUrl));
      final response = await request.close().timeout(
            const Duration(seconds: 30),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Wallpaper store failed: ${response.statusCode}');
      }
      final text = await response.transform(utf8.decoder).join();
      final data = jsonDecode(text) as List<dynamic>;
      return _itemsFromUrls(data.map((item) => item.toString()).toList());
    } catch (_) {
      return _itemsFromUrls(fallbackUrls);
    }
  }

  static List<WallpaperItem> _itemsFromUrls(List<String> urls) {
    return urls
        .where((url) => url.startsWith('http://') || url.startsWith('https://'))
        .map((url) {
      final uri = Uri.parse(url);
      final fileName = uri.pathSegments.isEmpty
          ? 'wallpaper'
          : uri.pathSegments.last.split('?').first;
      final title = _titleFromFileName(fileName);
      final ext = _extension(fileName);
      return WallpaperItem(
        id: fileName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_'),
        title: title,
        collection: ext == 'gif' ? 'Live' : 'ProxyCloud',
        imageUrl: url,
        thumbnailUrl: url,
        isLive: ext == 'gif',
      );
    }).toList(growable: false);
  }

  static String _extension(String fileName) {
    final parts = fileName.toLowerCase().split('.');
    return parts.length < 2 ? '' : parts.last;
  }

  static String _titleFromFileName(String fileName) {
    final name = fileName
        .replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '')
        .replaceAll('_upscaled', '')
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .trim();
    if (name.isEmpty) return 'Wallpaper';
    return name
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  static Future<String> download(WallpaperItem item) async {
    final dir = await _wallpaperDir();
    final segments = Uri.parse(item.imageUrl).pathSegments;
    final ext = segments.isEmpty ? '' : _extension(segments.last);
    final file = File('${dir.path}/${item.id}.${ext.isEmpty ? 'jpg' : ext}');
    if (await file.exists()) return file.path;

    final request = await HttpClient().getUrl(Uri.parse(item.imageUrl));
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Wallpaper download failed: ${response.statusCode}');
    }
    final bytes = await consolidateHttpClientResponseBytes(response);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<bool> applyFile(String path) async {
    final result = await _channel.invokeMethod<bool>(
      'setWallpaperFromFile',
      {'path': path},
    );
    if (result ?? false) invalidateSystemWallpaperCache();
    return result ?? false;
  }

  static Future<bool> downloadAndApply(WallpaperItem item) async {
    final path = await download(item);
    return applyFile(path);
  }

  static Future<void> openSystemPicker() async {
    await _channel.invokeMethod<void>('changeWallpaper');
    invalidateSystemWallpaperCache();
  }

  static Uint8List? _systemWallpaperCache;
  static bool _systemWallpaperResolved = false;

  /// Cached so opaque surfaces (Spotlight, App Library, Minimal drawer) can show
  /// the wallpaper instantly on repeat opens without a channel round-trip or a
  /// black flash. Returns null when there is no static bitmap (e.g. a live
  /// wallpaper). Call [invalidateSystemWallpaperCache] after the user changes
  /// the wallpaper.
  static Future<Uint8List?> currentSystemWallpaper() async {
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
  }

  static Future<Directory> _wallpaperDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/wallpapers');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
