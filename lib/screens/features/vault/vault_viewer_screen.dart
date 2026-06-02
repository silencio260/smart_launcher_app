import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../services/launcher_service.dart';
import '../mini_app_chrome.dart';

/// Full-screen, swipeable viewer for vault media. Each item is decrypted to a
/// private cache file on demand: images zoom, videos play in-app, and other
/// file types offer an export. The decrypted cache is wiped by the vault when
/// it re-locks (see [LauncherService.clearVaultViewCache]).
class VaultViewerScreen extends StatefulWidget {
  final List<Map<String, Object?>> items;
  final int initialIndex;

  const VaultViewerScreen({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  @override
  State<VaultViewerScreen> createState() => _VaultViewerScreenState();
}

class _VaultViewerScreenState extends State<VaultViewerScreen> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _title =>
      widget.items[_index]['name']?.toString() ?? 'File';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.items.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, index) {
          final item = widget.items[index];
          return _ViewerPage(
            key: ValueKey(item['id']),
            id: item['id'].toString(),
            name: item['name']?.toString() ?? 'File',
            kind: item['kind']?.toString() ?? 'file',
          );
        },
      ),
    );
  }
}

class _ViewerPage extends StatefulWidget {
  final String id;
  final String name;
  final String kind;

  const _ViewerPage({
    super.key,
    required this.id,
    required this.name,
    required this.kind,
  });

  @override
  State<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<_ViewerPage> {
  String? _path;
  bool _failed = false;
  VideoPlayerController? _video;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final path = await LauncherService.vaultDecryptToCache(widget.id);
    if (!mounted) return;
    if (path == null) {
      setState(() => _failed = true);
      return;
    }
    if (widget.kind == 'video') {
      final controller = VideoPlayerController.file(File(path));
      try {
        await controller.initialize();
        if (!mounted) {
          controller.dispose();
          return;
        }
        controller.setLooping(true);
        setState(() {
          _path = path;
          _video = controller;
        });
        controller.play();
      } catch (_) {
        controller.dispose();
        if (mounted) setState(() => _failed = true);
      }
    } else {
      setState(() => _path = path);
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    await LauncherService.exportLockedFile(widget.id);
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _message(Icons.error_outline, "Couldn't open this file");
    }
    if (_path == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    switch (widget.kind) {
      case 'image':
        return InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(child: Image.file(File(_path!))),
        );
      case 'video':
        return _videoView();
      default:
        return _fileView();
    }
  }

  Widget _videoView() {
    final video = _video;
    if (video == null || !video.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return GestureDetector(
      onTap: () => setState(() {
        video.value.isPlaying ? video.pause() : video.play();
      }),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: video.value.aspectRatio,
              child: VideoPlayer(video),
            ),
          ),
          if (!video.value.isPlaying)
            const Icon(Icons.play_circle_fill,
                color: Colors.white70, size: 72),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              video,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Colors.white,
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined,
                color: Colors.white, size: 72),
            const SizedBox(height: 18),
            Text(
              widget.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'No preview for this file type.',
              textAlign: TextAlign.center,
              style: TextStyle(color: miniAppMuted),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _exporting ? null : _export,
              style: FilledButton.styleFrom(
                backgroundColor: miniAppSurface2,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.ios_share),
              label: Text(_exporting ? 'Exporting…' : 'Export a copy'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: miniAppMuted, size: 56),
          const SizedBox(height: 14),
          Text(text, style: const TextStyle(color: miniAppMuted)),
        ],
      ),
    );
  }
}
