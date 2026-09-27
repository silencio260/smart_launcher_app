class WallpaperItem {
  final String id;
  final String title;
  final String collection;
  final String imageUrl;
  final String thumbnailUrl;
  final String assetPath;
  final bool isLive;
  final Map<String, dynamic> metadata;

  const WallpaperItem({
    required this.id,
    required this.title,
    required this.collection,
    required this.imageUrl,
    required this.thumbnailUrl,
    this.assetPath = '',
    this.isLive = false,
    this.metadata = const {},
  });

  factory WallpaperItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final image = Uri.tryParse(json['image_url'] as String? ?? '');
    final thumbnail = Uri.tryParse(json['thumbnail_url'] as String? ?? '');
    if ((id is! int && id is! String) ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch('$id') ||
        image == null ||
        image.scheme != 'https' ||
        image.host.isEmpty) {
      throw const FormatException('Invalid wallpaper metadata');
    }
    return WallpaperItem(
      id: 'nexwall_$id',
      title: json['title'] as String? ?? 'Wallpaper $id',
      metadata: Map.unmodifiable(json),
      collection: 'NexWall',
      imageUrl: image.toString(),
      thumbnailUrl:
          thumbnail != null &&
                  thumbnail.scheme == 'https' &&
                  thumbnail.host.isNotEmpty
              ? thumbnail.toString()
              : image.toString(),
    );
  }

  String get rightsText => wallpaperNoticeText({
    for (final entry in metadata.entries)
      if (RegExp(
        r'attribution|copyright|rights|license|credit|author|notice',
        caseSensitive: false,
      ).hasMatch(entry.key))
        entry.key: entry.value,
  });

  bool get isAsset => assetPath.isNotEmpty;
}

class WallpaperPage {
  final List<WallpaperItem> items;
  final List<WallpaperCategory> categories;
  final String snapshot;
  final int? nextPage;
  final DateTime expiresAt;
  final String environment;
  final List<dynamic> notices;

  const WallpaperPage({
    required this.items,
    required this.categories,
    required this.snapshot,
    required this.nextPage,
    required this.expiresAt,
    required this.environment,
    required this.notices,
  });

  factory WallpaperPage.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'] as Map<String, dynamic>;
    final freshness = json['freshness'] as Map<String, dynamic>;
    final snapshot = json['snapshot'] as String;
    final current = pagination['current_page'] as int;
    final last = pagination['last_page'] as int;
    final next = pagination['next_page'] as int?;
    if (snapshot.isEmpty ||
        current < 1 ||
        last < current ||
        (next != null && (next <= current || next > last))) {
      throw const FormatException('Invalid wallpaper pagination');
    }
    return WallpaperPage(
      items: (json['data'] as List)
          .cast<Map<String, dynamic>>()
          .where((item) => item['type'] == null || item['type'] == 'image')
          .map(WallpaperItem.fromJson)
          .toList(growable: false),
      categories: (json['categories'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(WallpaperCategory.fromJson)
          .toList(growable: false),
      snapshot: snapshot,
      nextPage: next,
      expiresAt: DateTime.parse(freshness['expires_at'] as String),
      environment: json['environment'] as String,
      notices: List.unmodifiable(json['notices'] as List? ?? const []),
    );
  }
}

class WallpaperCategory {
  final int id;
  final String name;
  final int? wallpaperCount;

  const WallpaperCategory({
    required this.id,
    required this.name,
    required this.wallpaperCount,
  });

  factory WallpaperCategory.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as int;
    final name = json['name'] as String;
    final count = json['wallpaper_count'];
    if (id < 1 ||
        name.trim().isEmpty ||
        (count != null && (count is! int || count < 0))) {
      throw const FormatException('Invalid wallpaper category');
    }
    return WallpaperCategory(id: id, name: name, wallpaperCount: count as int?);
  }
}

/// Render provider-supplied rights content without treating it as markup.
String wallpaperNoticeText(dynamic value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  if (value is List) {
    return value.map(wallpaperNoticeText).where((v) => v.isNotEmpty).join('\n');
  }
  if (value is Map) {
    return value.entries
        .map((entry) {
          final text = wallpaperNoticeText(entry.value);
          return text.isEmpty ? '' : '${entry.key}: $text';
        })
        .where((v) => v.isNotEmpty)
        .join('\n');
  }
  return value.toString();
}
