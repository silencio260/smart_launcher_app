import 'package:flutter/material.dart';
import '../../models/app_info.dart';
import '../../models/launcher_settings.dart';
import '../icons/bubble_text_view.dart';
import 'all_apps_grid_adapter.dart';

class AllAppsRecycler extends StatelessWidget {
  final List<AppInfo> apps;
  final LauncherSettings settings;
  final Map<String, int> badgeCounts;
  final void Function(AppInfo app) onAppTap;
  final void Function(AppInfo app) onAppLongPress;
  final ScrollController? scrollController;

  const AllAppsRecycler({
    super.key,
    required this.apps,
    required this.settings,
    required this.badgeCounts,
    required this.onAppTap,
    required this.onAppLongPress,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final items = buildSections(apps, settings.drawerColumns);

    return Scrollbar(
      controller: scrollController,
      thumbVisibility: settings.drawerShowScrollbar,
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        ...item.apps.map((app) => Expanded(
                              child: Center(
                                child: BubbleTextView(
                                  app: app,
                                  iconSize: settings.drawerIconSize,
                                  showLabel: settings.showDrawerLabels,
                                  iconShape: settings.iconShape,
                                  badgeCount: badgeCounts[app.packageName] ?? 0,
                                  onTap: () => onAppTap(app),
                                  onLongPress: () => onAppLongPress(app),
                                ),
                              ),
                            )),
                        // Fill remaining columns with empty space
                        ...List.generate(
                          settings.drawerColumns - item.apps.length,
                          (_) => const Expanded(child: SizedBox.shrink()),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
              childCount: items.length,
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
  }
}
