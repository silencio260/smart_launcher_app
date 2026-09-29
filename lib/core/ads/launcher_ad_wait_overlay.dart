import 'package:flutter/material.dart';

/// Keeps a tapped destination visually pending while an eligible ad loads.
class LauncherAdWaitOverlay extends StatelessWidget {
  const LauncherAdWaitOverlay({super.key});

  @override
  Widget build(BuildContext context) => const Positioned.fill(
    child: Stack(
      children: [
        ModalBarrier(color: Colors.black26, dismissible: false),
        Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      ],
    ),
  );
}
