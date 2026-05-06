import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../state/settings_cubit.dart';
import 'general_settings_screen.dart';
import 'home_screen_settings_screen.dart';
import 'smartspace_settings_screen.dart';
import 'dock_settings_screen.dart';
import 'drawer_settings_screen.dart';
import 'search_settings_screen.dart';
import 'folder_settings_screen.dart';
import 'gesture_settings_screen.dart';
import 'recents_settings_screen.dart';
import 'backup_restore_screen.dart';
import 'about_screen.dart';

class SettingsRootScreen extends StatelessWidget {
  const SettingsRootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Launcher Settings'),
      ),
      body: BlocBuilder<SettingsCubit, dynamic>(
        builder: (context, _) {
          return ListView(
            children: [
              _Tile(
                icon: Icons.tune,
                title: 'General',
                subtitle: 'Theme, icons, badges',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const GeneralSettingsScreen())),
              ),
              _Tile(
                icon: Icons.home_outlined,
                title: 'Home Screen',
                subtitle: 'Grid, layout, wallpaper',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const HomeScreenSettingsScreen())),
              ),
              _Tile(
                icon: Icons.wb_sunny_outlined,
                title: 'Smartspace',
                subtitle: 'Clock, date, cards',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SmartspaceSettingsScreen())),
              ),
              _Tile(
                icon: Icons.dock,
                title: 'Dock',
                subtitle: 'Dock appearance and size',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DockSettingsScreen())),
              ),
              _Tile(
                icon: Icons.apps,
                title: 'App Drawer',
                subtitle: 'Layout, columns, hidden apps',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DrawerSettingsScreen())),
              ),
              _Tile(
                icon: Icons.search,
                title: 'Search',
                subtitle: 'Search bar and suggestions',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SearchSettingsScreen())),
              ),
              _Tile(
                icon: Icons.folder_outlined,
                title: 'Folders',
                subtitle: 'Folder style and grid size',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const FolderSettingsScreen())),
              ),
              _Tile(
                icon: Icons.swipe,
                title: 'Gestures',
                subtitle: 'Swipes, double-tap, buttons',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const GestureSettingsScreen())),
              ),
              _Tile(
                icon: Icons.history,
                title: 'Recents',
                subtitle: 'Recent apps behavior',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const RecentsSettingsScreen())),
              ),
              const Divider(),
              _Tile(
                icon: Icons.backup_outlined,
                title: 'Backup & Restore',
                subtitle: 'Export or import settings',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const BackupRestoreScreen())),
              ),
              _Tile(
                icon: Icons.info_outline,
                title: 'About',
                subtitle: 'Version and credits',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AboutScreen())),
              ),
              const Divider(),
              _Tile(
                icon: Icons.science_outlined,
                title: 'Developer Options',
                subtitle: 'Experimental features',
                onTap: () => _showDeveloperOptions(context),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDeveloperOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Developer Options'),
        content: const Text('Experimental features are not yet available.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
