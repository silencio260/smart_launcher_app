import 'package:flutter/material.dart';

const miniAppBackground = Color(0xFF000000);
const miniAppSurface = Color(0xFF1C1C1E);
const miniAppSurface2 = Color(0xFF2A2A2D);
const miniAppAccent = Color(0xFFF5A623);
const miniAppMuted = Color(0xFF8E8E93);

class MiniAppScrollBehavior extends MaterialScrollBehavior {
  const MiniAppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class MiniAppScaffold extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final Widget child;
  final Widget? bottomNavigationBar;

  const MiniAppScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.bottomNavigationBar,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: miniAppBackground,
        colorScheme: const ColorScheme.dark(
          primary: miniAppAccent,
          surface: miniAppSurface,
          surfaceTint: Colors.transparent,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: miniAppBackground,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? Colors.white : null,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? miniAppAccent : null,
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: miniAppBackground,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          centerTitle: false,
          actions: actions,
        ),
        body: SafeArea(
          top: false,
          child: ScrollConfiguration(
            behavior: const MiniAppScrollBehavior(),
            child: child,
          ),
        ),
        bottomNavigationBar: bottomNavigationBar == null
            ? null
            : SafeArea(top: false, child: bottomNavigationBar!),
      ),
    );
  }
}

class MiniCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const MiniCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: miniAppSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: card,
    );
  }
}

class PermissionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const PermissionPill({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MiniCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: miniAppAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          Text(value, style: const TextStyle(color: miniAppMuted)),
          const Icon(Icons.chevron_right, color: miniAppMuted),
        ],
      ),
    );
  }
}

class EmptyMiniState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyMiniState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: miniAppAccent, size: 56),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: miniAppMuted, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
