class WallpaperItem {
  final String id;
  final String title;
  final String collection;
  final String imageUrl;
  final String thumbnailUrl;
  final String assetPath;
  final bool isLive;

  const WallpaperItem({
    required this.id,
    required this.title,
    required this.collection,
    required this.imageUrl,
    required this.thumbnailUrl,
    this.assetPath = '',
    this.isLive = false,
  });

  bool get isAsset => assetPath.isNotEmpty;
}
