import 'dart:typed_data';

enum SearchResultType { app, shortcut, contact, calculator, file, webSearch }

class SearchResult {
  final SearchResultType type;
  final String title;
  final String? subtitle;
  final Uint8List? icon;
  final String? iconPath;
  final String? packageName;
  final String? componentName;
  final String? shortcutId;
  final String? query;
  final double score;

  const SearchResult({
    required this.type,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconPath,
    this.packageName,
    this.componentName,
    this.shortcutId,
    this.query,
    this.score = 0,
  });
}
