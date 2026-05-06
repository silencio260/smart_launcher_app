import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_info.dart';
import '../services/launcher_service.dart';
import '../widgets/clock_widget.dart';
import '../widgets/app_icon.dart';
import 'app_drawer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<AppInfo> _apps = [];
  bool _loading = true;

  // Pinned dock packages — shown at bottom even without app drawer open
  static const _defaultDockPackages = [
    'com.android.dialer',
    'com.android.contacts',
    'com.android.messaging',
    'com.android.chrome',
    'com.android.camera2',
  ];

  List<AppInfo> get _dockApps {
    final dockPkgs = _defaultDockPackages.toSet();
    final pinned = _apps.where((a) => dockPkgs.contains(a.packageName)).toList();
    // Fallback: first 5 apps if none of the defaults are installed
    if (pinned.isEmpty && _apps.isNotEmpty) {
      return _apps.take(5).toList();
    }
    return pinned;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));
    _loadApps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadApps();
    }
  }

  Future<void> _loadApps() async {
    try {
      final apps = await LauncherService.getInstalledApps();
      if (mounted) setState(() { _apps = apps; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => AppDrawer(apps: _apps),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
            _openDrawer();
          }
        },
        onLongPress: () => _showHomeMenu(),
        child: Stack(
          children: [
            // Clock in upper-center
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 0,
              right: 0,
              child: const ClockWidget(),
            ),

            // Loading indicator
            if (_loading)
              const Center(child: CircularProgressIndicator(color: Colors.white54)),

            // Dock at bottom
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 16,
              right: 16,
              child: _Dock(apps: _dockApps, onSwipeUp: _openDrawer),
            ),

            // Swipe-up hint
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 88,
              left: 0,
              right: 0,
              child: const Center(
                child: Icon(Icons.keyboard_arrow_up, color: Colors.white38, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHomeMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _HomeMenu(onWallpaper: () {
        Navigator.pop(context);
        LauncherService.changeWallpaper();
      }),
    );
  }
}

class _Dock extends StatelessWidget {
  final List<AppInfo> apps;
  final VoidCallback onSwipeUp;

  const _Dock({required this.apps, required this.onSwipeUp});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragEnd: (d) {
        if (d.primaryVelocity != null && d.primaryVelocity! < -200) onSwipeUp();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: apps.map((a) => AppIcon(app: a, showLabel: false, iconSize: 48)).toList(),
        ),
      ),
    );
  }
}

class _HomeMenu extends StatelessWidget {
  final VoidCallback onWallpaper;
  const _HomeMenu({required this.onWallpaper});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900]!.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.wallpaper, color: Colors.white70),
            title: const Text('Change Wallpaper', style: TextStyle(color: Colors.white)),
            onTap: onWallpaper,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
