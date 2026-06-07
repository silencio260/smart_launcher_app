import 'package:shared_preferences/shared_preferences.dart';

/// Tiny persistence helper for the Smart-search "Recent searches" chips. Stores
/// the most recent queries (most-recent-first, de-duplicated, capped).
class RecentSearchesStore {
  static const _key = 'smart_search_recents_v1';
  static const _max = 8;

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const <String>[];
  }

  Future<List<String>> add(String query) async {
    final q = query.trim();
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key) ?? <String>[];
    if (q.isEmpty) return current;
    current.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    current.insert(0, q);
    final trimmed = current.take(_max).toList();
    await prefs.setStringList(_key, trimmed);
    return trimmed;
  }

  Future<List<String>> remove(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key) ?? <String>[];
    current.removeWhere((e) => e == query);
    await prefs.setStringList(_key, current);
    return current;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
