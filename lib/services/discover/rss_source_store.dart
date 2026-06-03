import 'package:shared_preferences/shared_preferences.dart';

/// A named feed the user can add with one tap (and the seed/default set).
class RssPreset {
  final String name;
  final String url;
  const RssPreset(this.name, this.url);
}

/// Persists the user's Discover feed sources (RSS/Atom URLs). Seeds a curated
/// set of well-known feeds on first run so the feed isn't empty out of the box.
class RssSourceStore {
  static const _key = 'discover_rss_sources_v1';
  static const _seededKey = 'discover_rss_seeded_v1';

  /// A broad, categorized catalog of popular feeds offered as one-tap presets.
  static const List<RssPreset> catalog = <RssPreset>[
    // World & general news
    RssPreset('BBC News', 'https://feeds.bbci.co.uk/news/rss.xml'),
    RssPreset('The Guardian', 'https://www.theguardian.com/world/rss'),
    RssPreset('NPR News', 'https://feeds.npr.org/1001/rss.xml'),
    RssPreset('CNN', 'http://rss.cnn.com/rss/cnn_topstories.rss'),
    RssPreset('New York Times',
        'https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml'),
    RssPreset('Al Jazeera', 'https://www.aljazeera.com/xml/rss/all.xml'),
    RssPreset('Deutsche Welle', 'https://rss.dw.com/rdf/rss-en-all'),
    // Technology
    RssPreset(
        'Ars Technica', 'https://feeds.arstechnica.com/arstechnica/index'),
    RssPreset('Hacker News', 'https://hnrss.org/frontpage'),
    RssPreset('TechCrunch', 'https://techcrunch.com/feed/'),
    RssPreset('Wired', 'https://www.wired.com/feed/rss'),
    RssPreset('Engadget', 'https://www.engadget.com/rss.xml'),
    RssPreset('Android Police', 'https://www.androidpolice.com/feed/'),
    RssPreset('9to5Google', 'https://9to5google.com/feed/'),
    RssPreset('MacRumors', 'https://feeds.macrumors.com/MacRumors-All'),
    // Business & finance
    RssPreset(
        'CNBC', 'https://www.cnbc.com/id/100003114/device/rss/rss.html'),
    RssPreset('Forbes', 'https://www.forbes.com/business/feed/'),
    // Science
    RssPreset('NASA', 'https://www.nasa.gov/rss/dyn/breaking_news.rss'),
    RssPreset('Science Daily', 'https://www.sciencedaily.com/rss/all.xml'),
    RssPreset('New Scientist', 'https://www.newscientist.com/feed/home/'),
    RssPreset('Nature', 'http://feeds.nature.com/nature/rss/current'),
    // Sports
    RssPreset('ESPN', 'https://www.espn.com/espn/rss/news'),
    RssPreset('BBC Sport', 'https://feeds.bbci.co.uk/sport/rss.xml'),
    RssPreset('Sky Sports', 'https://www.skysports.com/rss/12040'),
    // Entertainment & games
    RssPreset('Variety', 'https://variety.com/feed/'),
    RssPreset('IGN', 'https://feeds.ign.com/ign/all'),
    RssPreset('Polygon', 'https://www.polygon.com/rss/index.xml'),
    RssPreset('Rolling Stone', 'https://www.rollingstone.com/feed/'),
    // Health
    RssPreset(
        'Medical News Today', 'https://www.medicalnewstoday.com/rss'),
  ];

  /// The feeds seeded on first run: BBC News, TechCrunch and IGN.
  static const List<String> defaults = <String>[
    'https://feeds.bbci.co.uk/news/rss.xml',
    'https://techcrunch.com/feed/',
    'https://feeds.ign.com/ign/all',
  ];

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seededKey) != true && !prefs.containsKey(_key)) {
      const seed = defaults;
      await prefs.setStringList(_key, seed);
      await prefs.setBool(_seededKey, true);
      return seed;
    }
    final stored = prefs.getStringList(_key) ?? const <String>[];
    // Drop any Google News feed seeded by an earlier version — it's no longer
    // an offered source, so it shouldn't linger in existing installs.
    final cleaned =
        stored.where((u) => !u.contains('news.google.com')).toList();
    if (cleaned.length != stored.length) {
      await prefs.setStringList(_key, cleaned);
    }
    return cleaned;
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
