import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../services/icons/decoded_icon_cache.dart';
import '../../services/icons/icon_shape.dart';

class ShapedIcon extends StatefulWidget {
  final Uint8List? iconBytes;
  final String shape;
  final double size;

  /// Optional stable cache key (typically the package name). When provided,
  /// the icon is decoded once via [DecodedIconCache] and rendered with
  /// [RawImage] — no Image.memory rebuilds, no PNG re-decode per cache miss.
  final String? cacheKey;

  const ShapedIcon({
    super.key,
    required this.iconBytes,
    required this.shape,
    required this.size,
    this.cacheKey,
  });

  @override
  State<ShapedIcon> createState() => _ShapedIconState();
}

class _ShapedIconState extends State<ShapedIcon> {
  ui.Image? _image;
  String? _activeKey;
  int? _activePx;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureImage();
  }

  @override
  void didUpdateWidget(covariant ShapedIcon old) {
    super.didUpdateWidget(old);
    _ensureImage();
  }

  void _ensureImage() {
    final bytes = widget.iconBytes;
    final key = widget.cacheKey;
    if (bytes == null || key == null) return;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final targetPx = (widget.size * dpr).ceil().clamp(1, 512);
    if (key == _activeKey && targetPx == _activePx && _image != null) {
      return;
    }
    _activeKey = key;
    _activePx = targetPx;
    final cached = DecodedIconCache.instance.peek(key, targetPx);
    if (cached != null) {
      _image = cached;
      return;
    }
    DecodedIconCache.instance
        .getOrDecode(key, bytes, targetPx)
        .then((img) {
      if (!mounted) return;
      if (key != _activeKey || targetPx != _activePx) return;
      setState(() => _image = img);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final inner = SizedBox(
      width: widget.size,
      height: widget.size,
      child: _buildInner(context),
    );
    return _wrapInShapeClip(inner, widget.shape, widget.size);
  }

  Widget _buildInner(BuildContext context) {
    final bytes = widget.iconBytes;
    if (bytes == null) return _FallbackIcon(size: widget.size);

    // RawImage fast path: decoded ui.Image cached by package+pixel size.
    if (widget.cacheKey != null && _image != null) {
      return RawImage(
        image: _image,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    }

    // Fallback for callers without a cache key, or while the decode is in
    // flight on first paint. Image.memory still uses Flutter's image cache.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Image.memory(
      bytes,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      cacheWidth: (widget.size * dpr).ceil(),
      cacheHeight: (widget.size * dpr).ceil(),
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    );
  }
}

/// Wrap [child] in the cheapest clip primitive that matches [shape]:
/// ClipRRect/ClipOval for primitive shapes (hardware fast path), ClipPath
/// only for genuinely organic shapes that aren't expressible as an RRect.
Widget _wrapInShapeClip(Widget child, String shape, double size) {
  switch (shape) {
    case 'circle':
      return ClipOval(child: child);
    case 'square':
      return child; // no clip needed
    case 'rounded_square':
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: child,
      );
    case 'cupertino':
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.224),
        child: child,
      );
    case 'vessel':
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.3),
        child: child,
      );
    case 'squircle':
    case 'sammy':
      // Superellipse — visually very close to a 22.5% rounded square.
      // Approximating with ClipRRect saves ~200 path segments per icon.
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.225),
        child: child,
      );
    default:
      return ClipPath(
        clipper: _IconShapeClipper(shape: shape, size: size),
        child: child,
      );
  }
}

class _IconShapeClipper extends CustomClipper<Path> {
  final String shape;
  final double size;

  const _IconShapeClipper({required this.shape, required this.size});

  @override
  Path getClip(Size s) => IconShape.forKey(shape).getMaskPath(s.width);

  @override
  bool shouldReclip(_IconShapeClipper old) =>
      old.shape != shape || old.size != size;
}

class _FallbackIcon extends StatelessWidget {
  final double size;
  const _FallbackIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: Colors.grey[700],
      child: Icon(Icons.android, size: size * 0.6, color: Colors.white54),
    );
  }
}
