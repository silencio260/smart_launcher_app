import 'package:flutter/material.dart';

/// A single tappable row inside [AppContextMenu]. Set [destructive] for
/// actions like Uninstall so they render in a warning colour.
class AppMenuAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const AppMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
}

/// Shared long-press menu card used by both the home screen and the app
/// drawer. Render this inside a positioned overlay with a full-screen
/// tap-to-dismiss barrier behind it (see the call sites). Keeping the card in
/// one place keeps the two surfaces visually identical.
class AppContextMenu extends StatelessWidget {
  final String title;
  final List<AppMenuAction> actions;
  final double width;

  const AppContextMenu({
    super.key,
    required this.title,
    required this.actions,
    this.width = 224,
  });

  static const Color _destructive = Color(0xFFFF6B6B);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: const Color(0xFF1F2024).withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          boxShadow: const [
            BoxShadow(
                color: Colors.black54, blurRadius: 18, offset: Offset(0, 6)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            const SizedBox(height: 4),
            for (final action in actions) _Row(action: action),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final AppMenuAction action;
  const _Row({required this.action});

  @override
  Widget build(BuildContext context) {
    final color =
        action.destructive ? AppContextMenu._destructive : Colors.white;
    return InkWell(
      onTap: action.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Icon(action.icon,
                color: color.withValues(alpha: action.destructive ? 0.95 : 0.8),
                size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                action.label,
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
