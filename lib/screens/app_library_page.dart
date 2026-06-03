import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/app_info.dart';
import '../models/launcher_settings.dart';
import '../services/app_categories.dart';
import '../state/apps_cubit.dart';
import '../state/settings_cubit.dart';
import '../widgets/allapps/all_apps_grid_adapter.dart';
import '../widgets/icons/feature_icon.dart';
import '../widgets/icons/shaped_icon.dart';

/// A category folder in the App Library: a label plus the apps that fall under
/// it. The special "Hidden" folder collects apps the user hid from the drawer.
class _LibraryFolder {
  final String title;
  final List<AppInfo> apps;
  const _LibraryFolder(this.title, this.apps);
}

/// The far-right "App Library" special page: a black surface holding the
/// installed apps grouped into iOS-style category folders, followed by a full
/// A–Z app list mirroring the app drawer. Tapping a folder expands it into a
/// centered panel that behaves like a normal launcher folder, just bigger. This
/// is a non-editable system page — it is not part of the workspace layout.
class AppLibraryPage extends StatefulWidget {
  final void Function(AppInfo app) onLaunchApp;

  const AppLibraryPage({super.key, required this.onLaunchApp});

  @override
  State<AppLibraryPage> createState() => _AppLibraryPageState();
}

class _AppLibraryPageState extends State<AppLibraryPage> {
  // Folder display order — mirrors the seeded category page but with the
  // labels shown to the user in the library.
  static const _order = <AppCategory>[
    AppCategory.productivity,
    AppCategory.social,
    AppCategory.communication,
    AppCategory.google,
    AppCategory.video,
    AppCategory.music,
    AppCategory.photography,
    AppCategory.games,
    AppCategory.news,
    AppCategory.finance,
    AppCategory.shopping,
    AppCategory.travel,
    AppCategory.health,
    AppCategory.utility,
    AppCategory.tools,
    AppCategory.system,
    AppCategory.other,
  ];

  String _query = '';

  List<AppInfo> _visible(AppsState appsState, Set<String> hidden) => appsState
      .apps
      .where((a) =>
          !hidden.contains(a.launcherKey) && !hidden.contains(a.packageName))
      .toList();

  List<_LibraryFolder> _buildFolders(AppsState appsState, Set<String> hidden) {
    final visible = <AppInfo>[];
    final hiddenApps = <AppInfo>[];
    for (final app in appsState.apps) {
      if (hidden.contains(app.launcherKey) || hidden.contains(app.packageName)) {
        hiddenApps.add(app);
      } else {
        visible.add(app);
      }
    }
    final buckets = categorizeApps(visible);
    final folders = <_LibraryFolder>[];
    for (final category in _order) {
      final apps = buckets[category];
      if (apps == null || apps.isEmpty) continue;
      folders.add(_LibraryFolder(category.label, apps));
    }
    if (hiddenApps.isNotEmpty) {
      folders.add(_LibraryFolder('Hidden', hiddenApps));
    }
    return folders;
  }

  List<AppInfo> _filtered(AppsState appsState, Set<String> hidden) {
    final q = _query.toLowerCase();
    return appsState.apps
        .where((a) => a.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsCubit>().state;
    final hidden = settings.hiddenApps.toSet();
    return ColoredBox(
      color: Colors.black,
      child: BlocBuilder<AppsCubit, AppsState>(
        buildWhen: (a, b) => a.apps != b.apps,
        builder: (context, appsState) {
          return SafeArea(
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: _query.isEmpty
                  ? _browseSlivers(appsState, hidden, settings)
                  : _searchSlivers(_filtered(appsState, hidden)),
            ),
          );
        },
      ),
    );
  }

  // ── Browse mode: category folders, then an A–Z drawer-style app list ────────
  List<Widget> _browseSlivers(
    AppsState appsState,
    Set<String> hidden,
    LauncherSettings settings,
  ) {
    final folders = _buildFolders(appsState, hidden);
    final apps = _visible(appsState, hidden);
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        sliver: SliverToBoxAdapter(child: _buildSearchField()),
      ),
      if (folders.isNotEmpty) ...[
        const SliverToBoxAdapter(child: _SectionLabel('Categories')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.92,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _FolderTile(
                folder: folders[i],
                onTap: () => _openFolder(folders[i]),
              ),
              childCount: folders.length,
            ),
          ),
        ),
      ],
      const SliverToBoxAdapter(child: _SectionLabel('All apps')),
      ..._appListSlivers(apps, settings),
      const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
    ];
  }

  // ── Search mode: a single flat grid of matches ──────────────────────────────
  List<Widget> _searchSlivers(List<AppInfo> apps) {
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        sliver: SliverToBoxAdapter(child: _buildSearchField()),
      ),
      if (apps.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text('No matches', style: TextStyle(color: Colors.white54)),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _AppTile(app: apps[i], onTap: widget.onLaunchApp),
              childCount: apps.length,
            ),
          ),
        ),
    ];
  }

  // A–Z sectioned app list (the same section/row layout as the app drawer).
  List<Widget> _appListSlivers(List<AppInfo> apps, LauncherSettings settings) {
    final columns = settings.drawerColumns;
    final items = buildSections(apps, columns);
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = items[index];
            if (item is SectionHeader) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 0, 4),
                child: Text(
                  item.letter,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }
            if (item is AppRow) {
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    for (final app in item.apps)
                      Expanded(
                        child: Center(
                          child: _AppTile(app: app, onTap: widget.onLaunchApp),
                        ),
                      ),
                    for (int i = 0; i < columns - item.apps.length; i++)
                      const Expanded(child: SizedBox.shrink()),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          },
          childCount: items.length,
        ),
      ),
    ];
  }

  Widget _buildSearchField() {
    return TextField(
      style: const TextStyle(color: Colors.white),
      textInputAction: TextInputAction.search,
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'App Library',
        hintStyle: const TextStyle(color: Colors.white54),
        prefixIcon: const Icon(Icons.search, color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  void _openFolder(_LibraryFolder folder) {
    // Behaves like a normal launcher folder — a centered panel that scales in
    // over a blurred, dim backdrop and dismisses on a tap/swipe outside — just
    // bigger, since the library categories hold far more apps than a home folder.
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: folder.title,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (context, anim, _, __) {
        final scale = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 8 * anim.value,
            sigmaY: 8 * anim.value,
          ),
          child: FadeTransition(
            opacity: anim,
            child: Center(
              child: ScaleTransition(
                scale: scale,
                child: _FolderPanel(
                  folder: folder,
                  onLaunch: widget.onLaunchApp,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Section label shown above the categories and the A–Z list.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// A single app icon + label that launches on tap. Used by the A–Z list and the
/// search grid.
class _AppTile extends StatelessWidget {
  final AppInfo app;
  final void Function(AppInfo app) onTap;
  const _AppTile({required this.app, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(app),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AppGlyph(app: app, size: 52),
          const SizedBox(height: 6),
          Text(
            app.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Raw app icon (feature-aware) with no label — the shared glyph used across the
/// library tiles and folder previews.
class _AppGlyph extends StatelessWidget {
  final AppInfo app;
  final double size;
  const _AppGlyph({required this.app, required this.size});

  @override
  Widget build(BuildContext context) {
    final featureId = app.launcherFeatureId;
    if (featureId != null) {
      return FeatureIcon(
        featureId: featureId,
        componentName: app.appComponentName,
        size: size,
      );
    }
    return ShapedIcon(
      iconBytes: app.icon,
      iconPath: app.iconPath,
      shape: 'squircle',
      size: size,
      cacheKey: app.packageName,
    );
  }
}

/// A single folder tile: a rounded container with a 2×2 preview of app icons and
/// the category name below.
class _FolderTile extends StatelessWidget {
  final _LibraryFolder folder;
  final VoidCallback onTap;

  const _FolderTile({required this.folder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final preview = folder.apps.take(4).toList();
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: GridView.count(
                  crossAxisCount: 2,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (var i = 0; i < 4; i++)
                      i < preview.length
                          ? _AppGlyph(app: preview[i], size: 34)
                          : const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            folder.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Expanded folder contents shown as a centered, frosted-glass panel — the same
/// look as a normal launcher folder, scaled up for the library's larger buckets.
class _FolderPanel extends StatelessWidget {
  final _LibraryFolder folder;
  final void Function(AppInfo app) onLaunch;
  const _FolderPanel({required this.folder, required this.onLaunch});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Material(
      type: MaterialType.transparency,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: size.width * 0.9,
            constraints: BoxConstraints(maxHeight: size.height * 0.72),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    folder.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: folder.apps.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.78,
                    ),
                    itemBuilder: (context, i) => _AppTile(
                      app: folder.apps[i],
                      onTap: (app) {
                        Navigator.of(context).pop();
                        onLaunch(app);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
