import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's Discover feed sources (RSS/Atom URLs). Seeds a small set
/// of well-known feeds on first run so the feed isn't empty out of the box.
class RssSourceStore {
  static const _key = 'discover_rss_sources_v1';
  static const _seededKey = 'discover_rss_seeded_v1';

  static const defaults = <String>[
    'https://feeds.bbci.co.uk/news/rss.xml',
    'https://www.theverge.com/rss/index.xml',
    'https://feeds.arstechnica.com/arstechnica/index',
  ];

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seededKey) != true && !prefs.containsKey(_key)) {
      await prefs.setStringList(_key, defaults);
      await prefs.setBool(_seededKey, true);
      return List<String>.from(defaults);
    }
    return prefs.getStringList(_key) ?? const <String>[];
  }

  Future<List<String>> add(String url) async {
    final u = url.trim();
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key) ?? <String>[];
    if (u.isEmpty || current.contains(u)) return current;
    current.add(u);
    await prefs.setStringList(_key, current);
    return current;
  }

  Future<List<String>> addAll(Iterable<String> urls) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key) ?? <String>[];
    for (final raw in urls) {
      final u = raw.trim();
      if (u.isNotEmpty && !current.contains(u)) current.add(u);
    }
    await prefs.setStringList(_key, current);
    return current;
  }

  Future<List<String>> remove(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key) ?? <String>[];
    current.remove(url);
    await prefs.setStringList(_key, current);
    return current;
  }

  /// Extracts feed URLs from an OPML document body (the `xmlUrl` attributes).
  static List<String> parseOpml(String opml) {
    return RegExp(r'xmlUrl="([^"]+)"', caseSensitive: false)
        .allMatches(opml)
        .map((m) => m.group(1)!)
        .where((u) => u.startsWith('http'))
        .toList();
  }
}
