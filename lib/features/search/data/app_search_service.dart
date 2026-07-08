import 'package:smart_launcher_app/core/models/app_info.dart';
import 'package:smart_launcher_app/features/search/domain/entities/search_result.dart';

class AppSearchService {
  List<SearchResult> search(
    List<AppInfo> apps,
    String query, {
    Set<String> hiddenPackages = const {},
  }) {
    if (query.isEmpty) return [];
    final q = query.toLowerCase();
    final results = <SearchResult>[];

    for (final app in apps) {
      if (hiddenPackages.contains(app.launcherKey) ||
          hiddenPackages.contains(app.packageName)) {
        continue;
      }
      final name = app.name.toLowerCase();
      double score = 0;
      if (name.startsWith(q)) {
        score = 1.0;
      } else if (name.contains(q)) {
        score = 0.6;
      } else {
        score = _levenshteinScore(name, q);
        if (score < 0.3) continue;
      }
      results.add(SearchResult(
        type: SearchResultType.app,
        title: app.name,
        icon: app.icon,
        iconPath: app.iconPath,
        packageName: app.packageName,
        componentName: app.launcherKey,
        score: score,
      ));
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(8).toList();
  }

  double _levenshteinScore(String s, String t) {
    if (s.isEmpty || t.isEmpty) return 0;
    if (s.length < t.length) return _levenshteinScore(t, s);
    final d = List<int>.generate(t.length + 1, (i) => i);
    for (var i = 1; i <= s.length; i++) {
      var prev = i;
      for (var j = 1; j <= t.length; j++) {
        final val = s[i - 1] == t[j - 1]
            ? d[j - 1]
            : 1 + [d[j - 1], d[j], prev].reduce((a, b) => a < b ? a : b);
        d[j - 1] = prev;
        prev = val;
      }
      d[t.length] = prev;
    }
    final maxLen = s.length > t.length ? s.length : t.length;
    return 1 - d[t.length] / maxLen;
  }
}
