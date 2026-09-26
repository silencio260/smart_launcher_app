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

  factory WallpaperItem.fromNexWall(Map<String, dynamic> json) {
    final id = json['id'];
    final image = Uri.tryParse(json['image_url'] as String? ?? '');
    final thumbnail = Uri.tryParse(json['thumbnail_url'] as String? ?? '');
    if (id is! int ||
        image == null ||
        image.scheme != 'https' ||
        image.host.isEmpty) {
      throw const FormatException('Invalid wallpaper metadata');
    }
    return WallpaperItem(
      id: 'nexwall_$id',
      title: 'Wallpaper $id',
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

  bool get isAsset => assetPath.isNotEmpty;
}

class WallpaperPage {
  final List<WallpaperItem> items;
  final int currentPage;
  final int lastPage;

  const WallpaperPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
  });

  bool get hasMore => currentPage < lastPage;
}
