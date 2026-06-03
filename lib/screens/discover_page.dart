import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../models/app_info.dart';
import '../models/rss_item.dart';
import '../services/discover/rss_service.dart';
import '../services/discover/rss_source_store.dart';
import '../state/apps_cubit.dart';
import '../state/settings_cubit.dart';
import '../widgets/icons/feature_icon.dart';
import '../widgets/icons/shaped_icon.dart';
import 'add_news_source_screen.dart';

/// The far-left "Discover" special page: a launcher-native scaffold (search,
/// suggested apps, a couple of info cards) plus a "For You" feed assembled from
/// the user's RSS sources. Not part of the workspace layout — it is a
/// non-editable system page reached only by swiping left of home page 0.
class DiscoverPage extends StatefulWidget {
  final VoidCallback onOpenSearch;
  final void Function(AppInfo app) onLaunchApp;

  const DiscoverPage({
    super.key,
    required this.onOpenSearch,
    required this.onLaunchApp,
  });

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  static const _system = MethodChannel('com.genrevibes.smartlauncher/system');

  final _sourceStore = RssSourceStore();
  final _searchController = TextEditingController();
  List<RssItem> _items = const [];
  bool _loading = true;
  String _appQuery = '';

  @override
  void initState() {
    super.initState();
    _items = List<RssItem>.from(RssService.instance.cached)..shuffle();
    // Defer the network fetch a beat so swiping onto the page stays smooth.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFeed());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFeed({bool force = false}) async {
    final sources = await _sourceStore.load();
    final items = await RssService.instance.fetch(sources, force: force);
    if (mounted) {
      setState(() {
        // Shuffle a copy on each load so every visit reads as a fresh feed
        // rather than the same date-sorted order. The service keeps the
        // canonical sorted list in its cache untouched.
        _items = List<RssItem>.from(items)..shuffle();
        _loading = false;
      });
    }
  }

  void _openArticle(RssItem item) {
    _system.invokeMethod('launchUrl', {'url': item.link});
  }

  Future<void> _manageSources() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddNewsSourceScreen()),
    );
    if (mounted) _loadFeed(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final hidden = context.watch<SettingsCubit>().state.hiddenApps.toSet();
    final visibleApps = context
        .watch<AppsCubit>()
        .state
        .apps
        .where((a) =>
            !hidden.contains(a.launcherKey) && !hidden.contains(a.packageName))
        .toList();
    final suggestions = visibleApps.take(8).toList();
    final query = _appQuery.trim().toLowerCase();
    final searching = query.isNotEmpty;

    // Solid Google-News-style dark surface so the wallpaper doesn't show through
    // and the feed reads as a content page, not a transparent overlay.
    return Container(
      color: const Color(0xFF202124),
      child: SafeArea(
      child: RefreshIndicator(
        onRefresh: () => _loadFeed(force: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            _searchBar(),
            const SizedBox(height: 20),
            if (searching)
              ..._buildAppResults(visibleApps, query)
            else ...[
              if (suggestions.isNotEmpty) ...[
                _sectionLabel('Suggestions'),
                const SizedBox(height: 10),
                _SuggestionsRow(apps: suggestions, onTap: widget.onLaunchApp),
                const SizedBox(height: 20),
              ],
              const _InfoCardsRow(),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _sectionLabel('For you')),
                  TextButton.icon(
                    onPressed: _manageSources,
                    icon: const Icon(Icons.tune,
                        size: 16, color: Colors.white70),
                    label: const Text('Sources',
                        style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ..._buildFeed(),
            ],
          ],
        ),
      ),
      ),
    );
  }

  List<Widget> _buildAppResults(List<AppInfo> apps, String query) {
    final matches =
        apps.where((a) => a.name.toLowerCase().contains(query)).toList();
    if (matches.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text('No apps found',
                style: TextStyle(color: Colors.white54)),
          ),
        ),
      ];
    }
    return [
      _sectionLabel('Apps'),
      const SizedBox(height: 10),
      _SuggestionsRow(apps: matches, onTap: widget.onLaunchApp),
    ];
  }

  List<Widget> _buildFeed() {
    if (_items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: _loading
                ? const CircularProgressIndicator(strokeWidth: 2)
                : Column(
                    children: [
                      const Text('No stories yet',
                          style: TextStyle(color: Colors.white54)),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _manageSources,
                        child: const Text('Add a news source'),
                      ),
                    ],
                  ),
          ),
        ),
      ];
    }
    return [
      for (final item in _items)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ArticleCard(item: item, onTap: () => _openArticle(item)),
        ),
    ];
  }

  Widget _searchBar() {
    return TextField(
      controller: _searchController,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      textInputAction: TextInputAction.search,
      onChanged: (value) => setState(() => _appQuery = value),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search apps',
        hintStyle: const TextStyle(color: Colors.white54, fontSize: 16),
        prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
        suffixIcon: _appQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _appQuery = '');
                  FocusScope.of(context).unfocus();
                },
              ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.12),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      );
}

class _SuggestionsRow extends StatelessWidget {
  final List<AppInfo> apps;
  final void Function(AppInfo app) onTap;

  const _SuggestionsRow({required this.apps, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: apps.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, i) {
        final app = apps[i];
        return GestureDetector(
          onTap: () => onTap(app),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              app.launcherFeatureId != null
                  ? FeatureIcon(
                      featureId: app.launcherFeatureId!,
                      componentName: app.appComponentName,
                      size: 48,
                    )
                  : ShapedIcon(
                      iconBytes: app.icon,
                      iconPath: app.iconPath,
                      shape: 'squircle',
                      size: 48,
                      cacheKey: app.packageName,
                    ),
              const SizedBox(height: 6),
              Text(
                app.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoCardsRow extends StatelessWidget {
  const _InfoCardsRow();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Row(
      children: [
        Expanded(
          child: _InfoCard(
            icon: Icons.calendar_today,
            title: DateFormat('EEEE').format(now),
            subtitle: DateFormat('MMMM d').format(now),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _InfoCard(
            icon: Icons.schedule,
            title: DateFormat('h:mm a').format(now),
            subtitle: 'Local time',
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          Text(subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final RssItem item;
  final VoidCallback onTap;

  const _ArticleCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final meta = [
      item.source,
      if (item.published != null) _relative(item.published!),
    ].join(' · ');
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.25,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              if (item.imageUrl != null) ...[
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    item.imageUrl!,
                    width: 84,
                    height: 84,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _relative(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
