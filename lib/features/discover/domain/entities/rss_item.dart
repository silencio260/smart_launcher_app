/// A single article parsed from an RSS/Atom feed, normalised for display in the
/// Discover "For You" feed.
class RssItem {
  final String title;
  final String link;
  final String source;
  final DateTime? published;
  final String? imageUrl;

  const RssItem({
    required this.title,
    required this.link,
    required this.source,
    this.published,
    this.imageUrl,
  });
}
