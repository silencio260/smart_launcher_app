class WallpaperItem {
  final String id;
  final String title;
  final String collection;
  final String imageUrl;
  final String thumbnailUrl;
  final bool isLive;

  const WallpaperItem({
    required this.id,
    required this.title,
    required this.collection,
    required this.imageUrl,
    required this.thumbnailUrl,
    this.isLive = false,
  });
}
