import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../services/wallpaper_service.dart';

class ThemedWallpaperBackground extends StatefulWidget {
  final String path;

  /// Optional bundled asset shown when [path] is empty/missing, before the
  /// gradient fallback. A missing asset degrades gracefully to the gradient.
  final String? assetFallback;

  /// When [path] is empty/missing, load the device's static system wallpaper
  /// before falling back to [assetFallback] / the gradient.
  final bool useSystemWallpaper;

  final bool blur;
  final double blurSigma;
  final List<Color> fallbackColors;

  /// If Android cannot expose a static wallpaper bitmap, paint nothing so the
  /// launcher's wallpaper window shows the current live/system wallpaper.
  final bool transparentSystemFallback;

  const ThemedWallpaperBackground({
    super.key,
    required this.path,
    this.assetFallback,
    this.useSystemWallpaper = false,
    this.blur = false,
    this.blurSigma = 12,
    this.fallbackColors = const [Color(0xFF151A1F), Color(0xFF364D45)],
    this.transparentSystemFallback = false,
  });

  @override
  State<ThemedWallpaperBackground> createState() =>
      _ThemedWallpaperBackgroundState();
}

class _ThemedWallpaperBackgroundState extends State<ThemedWallpaperBackground> {
  Uint8List? _systemBytes;
  bool _loadingSystem = false;

  bool get _hasFile => widget.path.isNotEmpty && File(widget.path).existsSync();

  @override
  void initState() {
    super.initState();
    // Seed from the synchronous cache so the very first frame already shows the
    // wallpaper (no black flash) on repeat opens.
    if (widget.useSystemWallpaper && !_hasFile) {
      _systemBytes = WallpaperService.cachedSystemWallpaper;
    }
    _maybeLoadSystem();
  }

  @override
  void didUpdateWidget(ThemedWallpaperBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.useSystemWallpaper != widget.useSystemWallpaper) {
      _maybeLoadSystem();
    }
  }

  void _maybeLoadSystem() {
    if (!widget.useSystemWallpaper || _hasFile || _loadingSystem) return;
    _loadingSystem = true;
    WallpaperService.currentSystemWallpaper().then((bytes) {
      if (!mounted) return;
      setState(() {
        _systemBytes = bytes;
        _loadingSystem = false;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _loadingSystem = false);
    });
  }

  Widget _gradient() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.fallbackColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_hasFile) {
      child = Image.file(
        File(widget.path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else if (widget.useSystemWallpaper && _systemBytes != null) {
      child = Image.memory(
        _systemBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _gradient(),
      );
    } else if (widget.useSystemWallpaper && widget.transparentSystemFallback) {
      child = const SizedBox.expand();
    } else if (widget.assetFallback != null &&
        widget.assetFallback!.isNotEmpty) {
      child = Image.asset(
        widget.assetFallback!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        // If the bundled wallpaper isn't present, fall back to the gradient
        // instead of throwing.
        errorBuilder: (context, error, stackTrace) => _gradient(),
      );
    } else {
      child = _gradient();
    }

    if (!widget.blur) return Positioned.fill(child: child);
    return Positioned.fill(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(
            sigmaX: widget.blurSigma, sigmaY: widget.blurSigma),
        child: child,
      ),
    );
  }
}
