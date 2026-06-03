import 'dart:ui';
import 'package:flutter/material.dart';

/// The permanent "Smart search" pill that lives on every home page, just below
/// the dock. It cannot be removed and never appears in the edit-mode item menu —
/// it is part of the home chrome, not the workspace layout. Tapping it opens the
/// Smart-search screen.
class SmartSearchPill extends StatelessWidget {
  final VoidCallback onTap;
  final String label;

  const SmartSearchPill({
    super.key,
    required this.onTap,
    this.label = 'Smart search',
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.white.withValues(alpha: 0.14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(28),
            child: Container(
              height: 52,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.search, size: 20, color: Colors.white70),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
