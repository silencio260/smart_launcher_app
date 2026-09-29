/// A single article parsed from an RSS/Atom feed, normalised for display in the
/// Discover "For You" feed.
class RssItem {
  final String title;
  final String link;
  final String source;
  final DateTime? published;
  final String? imageUrl;

  bool get hasImage {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.isScheme('https') || uri.isScheme('http')) &&
        uri.host.isNotEmpty;
  }

  const RssItem({
    required this.title,
    required this.link,
    required this.source,
    this.published,
    this.imageUrl,
  });
}
