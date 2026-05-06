import 'package:flutter/material.dart';
import '../../services/icons/icon_shape.dart';

class IconShapePickerScreen extends StatelessWidget {
  final String current;

  const IconShapePickerScreen({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    final shapes = IconShape.builtIn.entries.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Icon Shape')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.75,
        ),
        itemCount: shapes.length,
        itemBuilder: (context, i) {
          final key = shapes[i].key;
          final shape = shapes[i].value;
          final selected = key == current;
          return GestureDetector(
            onTap: () => Navigator.pop(context, key),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 2.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipPath(
                    clipper: _ShapeClipper(shape),
                    child: Container(
                      color: selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Colors.grey.shade300,
                      child: Icon(
                        Icons.android,
                        size: 36,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  key.replaceAll('_', '\n'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    fontWeight: selected ? FontWeight.bold : null,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ShapeClipper extends CustomClipper<Path> {
  final IconShape shape;
  const _ShapeClipper(this.shape);

  @override
  Path getClip(Size size) => shape.getMaskPath(size.width);

  @override
  bool shouldReclip(_ShapeClipper old) => old.shape != shape;
}
