import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../models/launcher_settings.dart';
import '../../state/apps_cubit.dart';
import '../../state/search_cubit.dart';
import 'all_apps_recycler.dart';
import 'all_apps_search_bar.dart';

class AllAppsContainer extends StatefulWidget {
  final LauncherSettings settings;
  final void Function(AppInfo app) onAppTap;
  final void Function(AppInfo app) onAppLongPress;

  const AllAppsContainer({
    super.key,
    required this.settings,
    required this.onAppTap,
    required this.onAppLongPress,
  });

  @override
  State<AllAppsContainer> createState() => _AllAppsContainerState();
}

class _AllAppsContainerState extends State<AllAppsContainer> {
  ScrollController? _scrollController;

  @override
  void initState() {
    super.initState();
    if (widget.settings.drawerRememberScroll) {
      _scrollController = ScrollController();
    }
  }

  @override
  void dispose() {
    _scrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: widget.settings.drawerBackgroundColor
              .withValues(alpha: widget.settings.drawerBackgroundOpacity),
          child: Column(
            children: [
              const SizedBox(height: 8),
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              const AllAppsSearchBar(),
              const SizedBox(height: 4),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return BlocBuilder<SearchCubit, SearchState>(
      builder: (context, searchState) {
        final appsState = context.watch<AppsCubit>().state;

        final displayApps = searchState.query.isEmpty
            ? appsState.apps.where((a) => !a.isHidden).toList()
            : context.read<AppsCubit>().searchApps(searchState.query);

        return AllAppsRecycler(
          apps: displayApps,
          settings: widget.settings,
          badgeCounts: appsState.badgeCounts,
          onAppTap: widget.onAppTap,
          onAppLongPress: widget.onAppLongPress,
          scrollController: _scrollController,
        );
      },
    );
  }
}
