import 'dart:async';
import 'package:smart_launcher_app/features/settings/presentation/bloc/wallpaper_feed_controller.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/core/models/wallpaper_item.dart';
import 'package:smart_launcher_app/core/services/wallpaper_api.dart';
import 'package:smart_launcher_app/core/services/wallpaper_service.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';

class _CategoryTab {
  const _CategoryTab(this.label, this.providerName, [this.verifiedId])
    : search = null;
  const _CategoryTab.search(this.label, String this.search)
    : providerName = null,
      verifiedId = null;

  final String label;
  final String? providerName;
  final int? verifiedId;

  /// Worker search term for categories NexWall refuses or doesn't list.
  final String? search;
}

const _categoryTabs = <_CategoryTab>[
  // Anime and Dark & Moody are refused by NexWall on the current plan, so
  // these go through search.
  _CategoryTab.search('Anime & Manga', 'anime'),
  _CategoryTab('Animal & Wildlife', 'Animals & Wildlife', 4),
  _CategoryTab.search('Dark & Moody', 'dark'),
  _CategoryTab('Minimalist', 'Minimalist', 12),
  _CategoryTab('Nature & Landscape', 'Nature & Landscapes', 13),
  _CategoryTab('Abstract & 3D', 'Abstract & 3D', 2),
  _CategoryTab('Cars & Bikes', 'Cars & Bikes', 8),
  _CategoryTab.search('Gaming', 'gaming'),
];

class WallpaperScreen extends StatefulWidget {
  const WallpaperScreen({super.key});

  @override
  State<WallpaperScreen> createState() => _WallpaperScreenState();
}

class _WallpaperScreenState extends State<WallpaperScreen> {
  late final WallpaperFeedController _feed;
  bool _pickingGalleryImage = false;

  @override
  void initState() {
    super.initState();
    _feed = WallpaperFeedController()..addListener(_onFeedChanged);
    _feed.refresh();
    _feed.loadCategories();
  }

  void _onFeedChanged() {
    if (mounted) setState(() {});
  }

  int? _categoryId(_CategoryTab tab) {
    if (tab.search != null) return null;
    for (final category in _feed.categories) {
      if (category.name.toLowerCase() == tab.providerName!.toLowerCase()) {
        return category.id;
      }
    }
    return tab.verifiedId;
  }

  /// Tabs the Worker can actually serve: plan-listed categories, plus search
  /// tabs whose term the Worker accepts (others stay hidden, not broken).
  Iterable<_CategoryTab> get _availableTabs => _categoryTabs.where(
    (tab) => workerSearchTerms.contains(tab.search) || _categoryId(tab) != null,
  );

  bool _isSelectedCategory(_CategoryTab tab) {
    if (tab.search != null) return _feed.selectedSearch == tab.search;
    final id = _categoryId(tab);
    return id != null && _feed.selectedCategoryId == id;
  }

  Future<void> _selectTab(_CategoryTab tab) async {
    if (tab.search != null) {
      await _feed.selectSearch(tab.search!);
      return;
    }
    var id = _categoryId(tab);
    if (id == null) {
      await _feed.loadCategories();
      if (!mounted) return;
      id = _categoryId(tab);
    }
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'NexWall does not include this category in the current API catalog.',
          ),
        ),
      );
      return;
    }
    _feed.selectCategory(id);
  }

  @override
  void dispose() {
    _feed.removeListener(_onFeedChanged);
    _feed.dispose();
    super.dispose();
  }

  void _openPreview(WallpaperItem item) {
    final expiresAt = _feed.expiresAt;
    if (expiresAt == null || !DateTime.now().isBefore(expiresAt)) return;
    final settings = context.read<SettingsCubit>();
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder:
            (_) => BlocProvider.value(
              value: settings,
              child: _WallpaperPreviewScreen(item: item, expiresAt: expiresAt),
            ),
      ),
    );
  }

  Future<void> _chooseFromGallery() async {
    if (_pickingGalleryImage) return;
    setState(() => _pickingGalleryImage = true);
    try {
      final path = await WallpaperService.pickFromGallery();
      if (!mounted || path == null) return;
      final applied = await WallpaperService.applyFile(path);
      if (!applied) throw StateError('Could not apply the selected image');
      if (!mounted) return;
      final settings = context.read<SettingsCubit>();
      await settings.update(settings.state.copyWith(customWallpaperPath: path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gallery wallpaper applied.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not use gallery image: $error')),
      );
    } finally {
      if (mounted) setState(() => _pickingGalleryImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wallpaper')),
      body: BlocBuilder<SettingsCubit, LauncherSettings>(
        builder: (context, settings) {
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _pickingGalleryImage ? null : _chooseFromGallery,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Choose from gallery'),
                        ),
                      ),
                      if (settings.customWallpaperPath.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Reset launcher wallpaper',
                          onPressed:
                              () => context.read<SettingsCubit>().update(
                                settings.copyWith(customWallpaperPath: ''),
                              ),
                          icon: const Icon(Icons.restart_alt_rounded),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Wallpapers'),
                      if (wallpaperNoticeText(_feed.notices).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(wallpaperNoticeText(_feed.notices)),
                        ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Trending'),
                        selected:
                            _feed.selectedCategoryId == null &&
                            _feed.selectedSearch == null,
                        onSelected:
                            _feed.loading
                                ? null
                                : (_) => _feed.selectCategory(null),
                      ),
                      for (final tab in _availableTabs) ...[
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text(tab.label),
                          selected: _isSelectedCategory(tab),
                          onSelected:
                              _feed.loading ? null : (_) => _selectTab(tab),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.62,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _WallpaperTile(
                      item: _feed.items[index],
                      onTap: () => _openPreview(_feed.items[index]),
                    ),
                    childCount: _feed.items.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child:
                          _feed.loading
                              ? const CircularProgressIndicator()
                              : _feed.error != null
                              ? Column(
                                children: [
                                  Text(
                                    _feed.error!.message,
                                    textAlign: TextAlign.center,
                                  ),
                                  TextButton(
                                    onPressed: _feed.loadMore,
                                    child: Text(
                                      _feed.needsReload
                                          ? 'Reload wallpapers'
                                          : 'Retry',
                                    ),
                                  ),
                                ],
                              )
                              : _feed.nextPage != null
                              ? OutlinedButton(
                                onPressed: _feed.loadMore,
                                child: const Text('Load more'),
                              )
                              : Text(
                                _feed.items.isEmpty
                                    ? 'No wallpapers available'
                                    : 'All wallpapers loaded',
                              ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WallpaperTile extends StatelessWidget {
  final WallpaperItem item;
  final VoidCallback onTap;

  const _WallpaperTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _WallpaperImage(item: item),
            Positioned(
              top: 8,
              right: 8,
              child:
                  item.isLive
                      ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.68),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            'Live',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                      : const SizedBox.shrink(),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black87],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WallpaperPreviewScreen extends StatefulWidget {
  final WallpaperItem item;

  final DateTime expiresAt;

  const _WallpaperPreviewScreen({required this.item, required this.expiresAt});

  @override
  State<_WallpaperPreviewScreen> createState() =>
      _WallpaperPreviewScreenState();
}

class _WallpaperPreviewScreenState extends State<_WallpaperPreviewScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  Timer? _expiryTimer;
  bool get _expired => !DateTime.now().isBefore(widget.expiresAt);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _expiryTimer = Timer(widget.expiresAt.difference(DateTime.now()), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _save({required bool deviceWallpaper}) async {
    if (_expired) {
      setState(() {});
      return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await WallpaperService.download(widget.item);
      if (!mounted || _expired) return;
      if (deviceWallpaper) {
        final ok = await WallpaperService.applyFile(path);
        if (!ok) throw Exception('Could not apply wallpaper');
      }
      if (!mounted || _expired) return;
      await context.read<SettingsCubit>().update(
        context.read<SettingsCubit>().state.copyWith(customWallpaperPath: path),
      );
      if (!mounted) return;
      messenger
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              deviceWallpaper
                  ? 'Device wallpaper applied.'
                  : 'Theme wallpaper saved.',
            ),
          ),
        );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      messenger
        ..removeCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Wallpaper failed: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // Image runs edge to edge, under the status bar and the app bar.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.item.title),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body:
          _expired
              ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'This selection expired. Reload wallpapers to continue.',
                      style: TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to wallpapers'),
                    ),
                  ],
                ),
              )
              : Stack(
                fit: StackFit.expand,
                children: [
                  _WallpaperImage(
                    item: widget.item,
                    fullResolution: true,
                    loadingColor: Colors.white,
                    brokenColor: Colors.white70,
                  ),
                  // Keeps the back button and title legible on bright images.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: MediaQuery.paddingOf(context).top + kToolbarHeight,
                    child: const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.black54, Colors.transparent],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: MediaQuery.of(context).padding.bottom + 16,
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white70),
                            ),
                            onPressed:
                                _busy
                                    ? null
                                    : () => _save(deviceWallpaper: false),
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('Use in launcher'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                _busy || widget.item.isLive
                                    ? null
                                    : () => _save(deviceWallpaper: true),
                            icon:
                                _busy
                                    ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Icon(Icons.check_rounded),
                            label: const Text('Set wallpaper'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
    );
  }
}

class _WallpaperImage extends StatelessWidget {
  final WallpaperItem item;
  final bool fullResolution;
  final Color? loadingColor;
  final Color? brokenColor;

  const _WallpaperImage({
    required this.item,
    this.fullResolution = false,
    this.loadingColor,
    this.brokenColor,
  });

  @override
  Widget build(BuildContext context) {
    if (item.isAsset) {
      return Image.asset(
        item.assetPath,
        fit: BoxFit.cover,
        errorBuilder:
            (_, __, ___) => Icon(Icons.broken_image, color: brokenColor),
      );
    }
    return CachedNetworkImage(
      imageUrl:
          !fullResolution && item.thumbnailUrl.isNotEmpty
              ? item.thumbnailUrl
              : item.imageUrl,
      fit: BoxFit.cover,
      placeholder:
          (_, __) => Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: loadingColor,
            ),
          ),
      errorWidget: (_, __, ___) => Icon(Icons.broken_image, color: brokenColor),
    );
  }
}
