import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/icons/icon_shape.dart';

class ShapedIcon extends StatelessWidget {
  final Uint8List? iconBytes;
  final String shape;
  final double size;

  const ShapedIcon({
    super.key,
    required this.iconBytes,
    required this.shape,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _IconShapeClipper(shape: shape, size: size),
      child: SizedBox(
        width: size,
        height: size,
        child: iconBytes != null
            ? Image.memory(iconBytes!, width: size, height: size, fit: BoxFit.cover)
            : _FallbackIcon(size: size),
      ),
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
  bool shouldReclip(_IconShapeClipper old) => old.shape != shape || old.size != size;
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
