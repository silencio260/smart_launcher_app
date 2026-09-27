import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:smart_launcher_app/core/config/app_env.dart';
import 'package:smart_launcher_app/core/models/wallpaper_item.dart';

enum WallpaperFailure {
  offline,
  unavailable,
  expired,
  throttled,
  invalidRequest,
  configuration,
}

class WallpaperApiException implements Exception {
  const WallpaperApiException(this.kind, this.message);
  final WallpaperFailure kind;
  final String message;

  @override
  String toString() => message;
}

/// Search terms the Wallpaper Worker accepts; it answers any other term with
/// 400 `invalid_search`. Add a term here once the Worker allowlists it.
const workerSearchTerms = {'gaming', 'anime', 'dark'};

class WallpaperApi {
  final _clients = <HttpClient>{};
  bool _closed = false;

  Future<List<WallpaperCategory>> fetchCategories() async {
    if (_closed) throw StateError('Wallpaper API is closed');
    final uri = _baseUri.replace(path: '/categories', queryParameters: null);
    final client =
        HttpClient()..connectionTimeout = const Duration(seconds: 12);
    _clients.add(client);
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw const WallpaperApiException(
            WallpaperFailure.unavailable,
            'Wallpaper categories are temporarily unavailable.',
          );
        }
        final json =
            jsonDecode(await response.transform(utf8.decoder).join())
                as Map<String, dynamic>;
        return (json['data'] as List)
            .cast<Map<String, dynamic>>()
            .map(WallpaperCategory.fromJson)
            .toList(growable: false);
      })().timeout(const Duration(seconds: 12));
    } on WallpaperApiException {
      rethrow;
    } catch (_) {
      throw const WallpaperApiException(
        WallpaperFailure.unavailable,
        'Wallpaper categories are temporarily unavailable.',
      );
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }

  Uri get _baseUri {
    if (AppEnv.wallpaperApiEnvironment == 'cloudflare') {
      return Uri.parse(
        'https://wallpaper-cache.wallpaper-cache-worker.workers.dev',
      );
    }
    if (AppEnv.wallpaperApiEnvironment == 'sandbox' && !kReleaseMode) {
      final uri = Uri.tryParse(AppEnv.wallpaperSandboxBaseUrl);
      if (uri != null &&
          ['http', 'https'].contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty &&
          !uri.hasQuery &&
          !uri.hasFragment) {
        return uri;
      }
    }
    throw const WallpaperApiException(
      WallpaperFailure.configuration,
      'Wallpaper service is not configured for this build.',
    );
  }

  Future<WallpaperPage> fetchPage({
    int page = 1,
    String? snapshot,
    int? categoryId,
    String? search,
  }) async {
    if (_closed) throw StateError('Wallpaper API is closed');
    if (page < 1 ||
        (page > 1 && snapshot == null) ||
        (categoryId != null && categoryId < 1) ||
        (search != null &&
            (!workerSearchTerms.contains(search) || categoryId != null))) {
      throw const WallpaperApiException(
        WallpaperFailure.invalidRequest,
        'Invalid wallpaper page. Reload the selection.',
      );
    }
    final uri = _baseUri.replace(
      path: '/wallpapers',
      queryParameters: {
        'page': '$page',
        if (snapshot != null) 'snapshot': snapshot,
        if (categoryId != null) 'category_id': '$categoryId',
        if (search != null) 'search': search,
      },
    );
    final client =
        HttpClient()..connectionTimeout = const Duration(seconds: 12);
    _clients.add(client);
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        if (kDebugMode) {
          debugPrint(
            '[Wallpaper] Worker page=$page HTTP ${response.statusCode}',
          );
        }
        switch (response.statusCode) {
          case 410:
            throw const WallpaperApiException(
              WallpaperFailure.expired,
              'This selection expired. Reload to see current wallpapers.',
            );
          case 429:
            final seconds = int.tryParse(
              response.headers.value('retry-after') ?? '',
            );
            throw WallpaperApiException(
              WallpaperFailure.throttled,
              seconds != null && seconds > 0
                  ? 'Too many requests. Try again in $seconds seconds.'
                  : 'Too many requests. Please wait before retrying.',
            );
          case 400:
            throw const WallpaperApiException(
              WallpaperFailure.invalidRequest,
              'The wallpaper request is invalid. Reload the selection.',
            );
          case 200:
            break;
          case 503:
            final body = await response.transform(utf8.decoder).join();
            String? code;
            try {
              final decoded = jsonDecode(body);
              if (decoded is Map<String, dynamic>) {
                final error = decoded['error'];
                if (error is Map<String, dynamic>) {
                  code = error['code'] as String?;
                }
              }
            } on FormatException {
              // Keep the standard unavailable message for non-JSON responses.
            }
            if (code == 'upstream_http_403' || code == 'production_forbidden') {
              throw const WallpaperApiException(
                WallpaperFailure.unavailable,
                'NexWall denied this wallpaper request. Check category access on your API plan.',
              );
            }
            throw const WallpaperApiException(
              WallpaperFailure.unavailable,
              'Wallpapers are temporarily unavailable. Please try again later.',
            );
          default:
            throw const WallpaperApiException(
              WallpaperFailure.unavailable,
              'Wallpapers are temporarily unavailable. Please try again later.',
            );
        }
        final json =
            jsonDecode(await response.transform(utf8.decoder).join())
                as Map<String, dynamic>;
        final result = WallpaperPage.fromJson(json);
        if (result.nextPage != null && result.nextPage! <= page) {
          throw const FormatException('Non-advancing wallpaper page');
        }
        return result;
      })().timeout(const Duration(seconds: 12));
    } on WallpaperApiException {
      rethrow;
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('[Wallpaper] Worker page=$page failed: $error');
        debugPrintStack(stackTrace: stack);
      }
      if (error is TimeoutException ||
          error is SocketException ||
          error is HandshakeException) {
        throw const WallpaperApiException(
          WallpaperFailure.offline,
          'Cannot connect to wallpapers. Check your connection and retry.',
        );
      }
      throw const WallpaperApiException(
        WallpaperFailure.unavailable,
        'The wallpaper service returned an invalid response. Please retry.',
      );
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }

  void close() {
    _closed = true;
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
  }
}
