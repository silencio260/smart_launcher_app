import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/rss_item.dart';

/// Fetches and parses RSS/Atom feeds with the built-in [HttpClient] (no extra
/// dependencies) and a tolerant regex parser. Results are cached in memory so
/// the Discover page doesn't re-hit the network on every rebuild.
class RssService {
  RssService._();
  static final RssService instance = RssService._();

  static const _ttl = Duration(hours: 1);
  static const _perFeedLimit = 12;
  static const _timeout = Duration(seconds: 10);

  List<RssItem> _cache = const [];
  DateTime? _fetchedAt;
  List<String> _cachedSources = const [];
  Future<List<RssItem>>? _inFlight;

  bool _isFresh(List<String> sources) =>
      _fetchedAt != null &&
      DateTime.now().difference(_fetchedAt!) < _ttl &&
      _listEquals(_cachedSources, sources);

  List<RssItem> get cached => _cache;

  /// Returns aggregated, date-sorted items for [sources]. Uses the cache when
  /// fresh unless [force] is set (pull-to-refresh).
  Future<List<RssItem>> fetch(List<String> sources, {bool force = false}) {
    if (!force && _isFresh(sources)) return Future.value(_cache);
    if (_inFlight != null && !force) return _inFlight!;
    final future = _fetchAll(sources);
    _inFlight = future;
    future.whenComplete(() => _inFlight = null);
    return future;
  }

  Future<List<RssItem>> _fetchAll(List<String> sources) async {
    final client = HttpClient()..userAgent = 'Mozilla/5.0 (SmartLauncher)';
    client.connectionTimeout = _timeout;
    final all = <RssItem>[];
    try {
      for (final url in sources) {
        try {
          final body = await _get(client, url);
          if (body == null) continue;
          all.addAll(_parse(body, url));
        } catch (_) {
          // Skip feeds that fail; the rest still render.
        }
      }
    } finally {
      client.close(force: true);
    }
    all.sort((a, b) {
      final ad = a.published ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.published ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    _cache = all;
    _fetchedAt = DateTime.now();
    _cachedSources = List<String>.from(sources);
    return all;
  }

  Future<String?> _get(HttpClient client, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    final request = await client.getUrl(uri).timeout(_timeout);
    request.headers.set(HttpHeaders.acceptHeader,
        'application/rss+xml, application/atom+xml, application/xml, text/xml');
    final response = await request.close().timeout(_timeout);
    if (response.statusCode != 200) return null;
    return response.transform(utf8.decoder).join().timeout(_timeout);
  }

  List<RssItem> _parse(String xml, String feedUrl) {
    final feedTitle = _firstTag(xml, 'title') ?? _host(feedUrl);
    final items = <RssItem>[];

    final blocks = <String>[
      ..._allBlocks(xml, 'item'),
      ..._allBlocks(xml, 'entry'),
    ];
    for (final block in blocks) {
      final title = _clean(_firstTag(block, 'title'));
      if (title == null || title.isEmpty) continue;
      final link = _resolveLink(block);
      final published = _parseDate(_firstTag(block, 'pubDate') ??
          _firstTag(block, 'published') ??
          _firstTag(block, 'updated') ??
          _firstTag(block, 'dc:date'));
      // Google News wraps each item with a per-article <source> (the original
      // publisher); prefer it so aggregated feeds credit the real outlet.
      final itemSource =
          _clean(_firstTag(block, 'source')) ?? _clean(feedTitle);
      items.add(RssItem(
        title: title,
        link: link ?? feedUrl,
        source: (itemSource != null && itemSource.isNotEmpty)
            ? itemSource
            : _host(feedUrl),
        published: published,
        imageUrl: _extractImage(block),
      ));
      if (items.length >= _perFeedLimit) break;
    }
    return items;
  }

  // ---- Tiny tolerant XML helpers -------------------------------------------

  List<String> _allBlocks(String xml, String tag) {
    final re = RegExp('<$tag[\\s>][\\s\\S]*?</$tag>', caseSensitive: false);
    return re.allMatches(xml).map((m) => m.group(0)!).toList();
  }

  String? _firstTag(String xml, String tag) {
    final re = RegExp('<$tag(?:\\s[^>]*)?>([\\s\\S]*?)</$tag>',
        caseSensitive: false);
    return re.firstMatch(xml)?.group(1)?.trim();
  }

  String? _resolveLink(String block) {
    final plain = _firstTag(block, 'link');
    if (plain != null && plain.isNotEmpty && plain.startsWith('http')) {
      return plain;
    }
    // Atom: <link href="..." />
    final href = RegExp(r'<link[^>]*href="([^"]+)"', caseSensitive: false)
        .firstMatch(block)
        ?.group(1);
    return href;
  }

  String? _extractImage(String block) {
    for (final attr in [
      RegExp(r'<media:content[^>]*url="([^"]+)"', caseSensitive: false),
      RegExp(r'<media:thumbnail[^>]*url="([^"]+)"', caseSensitive: false),
      RegExp(r'<enclosure[^>]*url="([^"]+\.(?:jpg|jpeg|png|webp)[^"]*)"',
          caseSensitive: false),
      RegExp(r'''<img[^>]*src=["']([^"']+)["']''', caseSensitive: false),
    ]) {
      final m = attr.firstMatch(block)?.group(1);
      if (m != null && m.startsWith('http')) return m;
    }
    return null;
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    return _parseRfc822(s);
  }

  // RFC-822 dates like "Tue, 02 Jun 2026 19:33:25 GMT".
  DateTime? _parseRfc822(String s) {
    final m = RegExp(
            r'(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?')
        .firstMatch(s);
    if (m == null) return null;
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final month = months[m.group(2)!.toLowerCase()];
    if (month == null) return null;
    return DateTime.utc(
      int.parse(m.group(3)!),
      month,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      m.group(6) != null ? int.parse(m.group(6)!) : 0,
    );
  }

  String? _clean(String? raw) {
    if (raw == null) return null;
    var s = raw;
    // Unwrap CDATA.
    s = s.replaceAll(RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>'), r'$1');
    // Strip any leftover tags.
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    // Decode the few common entities.
    s = s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ');
    return s.trim();
  }

  String _host(String url) => Uri.tryParse(url)?.host ?? url;

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
