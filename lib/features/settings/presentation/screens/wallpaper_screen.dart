import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/core/models/wallpaper_item.dart';
import 'package:smart_launcher_app/core/services/wallpaper_service.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';

class WallpaperScreen extends StatefulWidget {
  const WallpaperScreen({super.key});

  @override
  State<WallpaperScreen> createState() => _WallpaperScreenState();
}

class _WallpaperScreenState extends State<WallpaperScreen> {
  Future<Uint8List?>? _currentWallpaper;
  late Future<List<WallpaperItem>> _store;

  @override
  void initState() {
    super.initState();
    _currentWallpaper = WallpaperService.currentSystemWallpaper();
    _store = WallpaperService.fetchStore();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wallpaper')),
      body: BlocBuilder<SettingsCubit, LauncherSettings>(
        builder: (context, settings) {
          return FutureBuilder<List<WallpaperItem>>(
              future: _store,
              builder: (context, snapshot) {
                final wallpapers = snapshot.data;
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      sliver: SliverToBoxAdapter(
                        child: _CurrentWallpaperCard(
                          settings: settings,
                          currentWallpaper: _currentWallpaper,
                          onSystemPicker: () =>
                              WallpaperService.openSystemPicker(),
                          onReset: settings.customWallpaperPath.isEmpty
                              ? null
                              : () => context.read<SettingsCubit>().update(
                                    settings.copyWith(customWallpaperPath: ''),
                                  ),
                        ),
                      ),
                    ),
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'ProxyCloud wallpapers',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    if (wallpapers == null)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (wallpapers.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: Text('No wallpapers available')),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.72,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final item = wallpapers[index];
                              return _WallpaperTile(
                                item: item,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BlocProvider.value(
                                      value: context.read<SettingsCubit>(),
                                      child:
                                          _WallpaperPreviewScreen(item: item),
                                    ),
                                  ),
                                ),
                              );
                            },
                            childCount: wallpapers.length,
                          ),
                        ),
                      ),
                  ],
                );
              });
        },
      ),
    );
  }
}

class _CurrentWallpaperCard extends StatelessWidget {
  final LauncherSettings settings;
  final Future<Uint8List?>? currentWallpaper;
  final VoidCallback onSystemPicker;
  final VoidCallback? onReset;

  const _CurrentWallpaperCard({
    required this.settings,
    required this.currentWallpaper,
    required this.onSystemPicker,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.36),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _preview(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onSystemPicker,
                    icon: const Icon(Icons.wallpaper_outlined),
                    label: const Text('System picker'),
                  ),
                ),
                if (onReset != null) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Reset',
                    onPressed: onReset,
                    icon: const Icon(Icons.restart_alt_rounded),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview() {
    final path = settings.customWallpaperPath;
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }
    return FutureBuilder<Uint8List?>(
      future: currentWallpaper,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) {
          return Image.memory(bytes, fit: BoxFit.cover);
        }
        return const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF101820), Color(0xFF4B6B57)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        );
      },
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
              child: item.isLive
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.68),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                      Text(
                        item.collection,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
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

  const _WallpaperPreviewScreen({required this.item});

  @override
  State<_WallpaperPreviewScreen> createState() =>
      _WallpaperPreviewScreenState();
}

class _WallpaperPreviewScreenState extends State<_WallpaperPreviewScreen> {
  bool _busy = false;

  Future<void> _save({required bool deviceWallpaper}) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await WallpaperService.download(widget.item);
      if (deviceWallpaper) {
        final ok = await WallpaperService.applyFile(path);
        if (!ok) throw Exception('Could not apply wallpaper');
      }
      if (!mounted) return;
      context.read<SettingsCubit>().update(
            context
                .read<SettingsCubit>()
                .state
                .copyWith(customWallpaperPath: path),
          );
      messenger
        ..removeCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(deviceWallpaper
              ? 'Device wallpaper applied.'
              : 'Theme wallpaper saved.'),
        ));
      if (mounted) Navigator.pop(context);
    } catch (error) {
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
      appBar: AppBar(
        title: Text(widget.item.title),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _WallpaperImage(
            item: widget.item,
            loadingColor: Colors.white,
            brokenColor: Colors.white70,
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
                        _busy ? null : () => _save(deviceWallpaper: false),
                    icon: const Icon(Icons.download_rounded),
                    label:
                        Text(widget.item.isLive ? 'Live theme' : 'Theme wall'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy || widget.item.isLive
                        ? null
                        : () => _save(deviceWallpaper: true),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(widget.item.isLive ? 'Theme only' : 'Device'),
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
  final Color? loadingColor;
  final Color? brokenColor;

  const _WallpaperImage({
    required this.item,
    this.loadingColor,
    this.brokenColor,
  });

  @override
  Widget build(BuildContext context) {
    if (item.isAsset) {
      return Image.asset(
        item.assetPath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          Icons.broken_image,
          color: brokenColor,
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl:
          item.thumbnailUrl.isNotEmpty ? item.thumbnailUrl : item.imageUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: loadingColor,
        ),
      ),
      errorWidget: (_, __, ___) => Icon(
        Icons.broken_image,
        color: brokenColor,
      ),
    );
  }
}
