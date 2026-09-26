import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:smart_launcher_app/core/models/wallpaper_item.dart';

class WallpaperService {
  static const _channel = MethodChannel(
    'com.genrevibes.smartlauncher/wallpaper',
  );
  static const iosTemplateWallpaperAsset =
      'assets/ios_theme/wallpaper/ios_default.webp';
  static const sandboxUrl =
      'https://nexwall.kodnextech.com/wallpaper-api/sandbox';

  /// Uses NexWall's public sandbox, not its authenticated production API.
  static Future<WallpaperPage> fetchPage({int page = 1}) async {
    final uri = Uri.parse(sandboxUrl).replace(
      queryParameters: {
        'endpoint': 'wallpapers',
        'type': 'image',
        'per_page': '10',
        'page': '$page',
      },
    );
    final client =
        HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        final limit = response.headers.value('x-ratelimit-limit');
        final remaining = response.headers.value('x-ratelimit-remaining');
        final retryAfter = response.headers.value('retry-after');
        if (kDebugMode) {
          debugPrint(
            '[Wallpaper] page=$page HTTP ${response.statusCode} '
            'limit=$limit remaining=$remaining retryAfter=$retryAfter',
          );
        }
        if (response.statusCode == 429) {
          final seconds = int.tryParse(retryAfter ?? '');
          throw WallpaperRequestException(
            seconds != null && seconds > 0
                ? 'Wallpaper request limit reached. Try again in $seconds seconds.'
                : 'Wallpaper request limit reached. Please wait before retrying.',
          );
        }
        if (response.statusCode != HttpStatus.ok) {
          throw WallpaperRequestException(
            'Wallpaper service returned HTTP ${response.statusCode}. Please try again later.',
          );
        }
        final data =
            jsonDecode(await response.transform(utf8.decoder).join())
                as Map<String, dynamic>;
        if (data['status'] != 'success' || data['data'] is! List) {
          throw const FormatException('Invalid wallpaper response');
        }
        final items = (data['data'] as List)
            .cast<Map<String, dynamic>>()
            .where((item) => item['type'] == 'image')
            .map(WallpaperItem.fromNexWall)
            .toList(growable: false);
        return WallpaperPage(
          items: items,
          currentPage: (data['current_page'] as num).toInt(),
          lastPage: (data['last_page'] as num).toInt(),
        );
      })().timeout(const Duration(seconds: 30));
    } on TimeoutException catch (error, stack) {
      if (kDebugMode) {
        debugPrint('[Wallpaper] $error');
        debugPrintStack(stackTrace: stack);
      }
      throw const WallpaperRequestException(
        'The wallpaper request timed out. Check your connection and retry.',
      );
    } on SocketException catch (error, stack) {
      if (kDebugMode) {
        debugPrint('[Wallpaper] $error');
        debugPrintStack(stackTrace: stack);
      }
      throw const WallpaperRequestException(
        'Cannot connect to the wallpaper service. Check your internet connection and retry.',
      );
    } on HandshakeException catch (error, stack) {
      if (kDebugMode) {
        debugPrint('[Wallpaper] $error');
        debugPrintStack(stackTrace: stack);
      }
      throw const WallpaperRequestException(
        'Could not establish a secure connection to the wallpaper service.',
      );
    } finally {
      client.close(force: true);
    }
  }

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

  static Future<bool> applyFile(String path) async {
    final result = await _channel.invokeMethod<bool>('setWallpaperFromFile', {
      'path': path,
    });
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

class WallpaperRequestException implements Exception {
  final String message;

  const WallpaperRequestException(this.message);

  @override
  String toString() => message;
}
