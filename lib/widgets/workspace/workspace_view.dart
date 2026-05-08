import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../models/launcher_settings.dart';
import '../../services/drag/drag_controller.dart';
import '../../state/workspace_cubit.dart';
import 'cell_layout.dart';

class WorkspaceView extends StatefulWidget {
  final LauncherSettings settings;
  final DragController dragController;
  final Map<String, int> badgeCounts;
  final void Function(AppInfo app) onAppTap;
  final void Function(AppInfo app, int page, int slot, Offset iconCenter) onAppLongPress;
  final void Function(double offset) onPageChanged;
  final void Function(PageController)? onControllerReady;

  const WorkspaceView({
    super.key,
    required this.settings,
    required this.dragController,
    required this.badgeCounts,
    required this.onAppTap,
    required this.onAppLongPress,
    required this.onPageChanged,
    this.onControllerReady,
  });

  @override
  State<WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<WorkspaceView> {
  late PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onControllerReady?.call(_controller);
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pages = context.read<WorkspaceCubit>().state.pages.length;
    if (!_controller.hasClients || pages == 0) return;
    final page = _controller.page ?? 0;
    widget.onPageChanged(pages > 1 ? page / (pages - 1) : 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, state) {
        if (state.pages.isEmpty) {
          return const SizedBox.shrink();
        }
        return PageView.builder(
          controller: _controller,
          physics: const BouncingScrollPhysics(),
          onPageChanged: (i) => context.read<WorkspaceCubit>().setCurrentPage(i),
          itemCount: widget.settings.infiniteScrolling ? null : state.pages.length,
          itemBuilder: (context, rawIndex) {
            final i = rawIndex % state.pages.length;
            return CellLayoutView(
              page: state.pages[i],
              pageIndex: i,
              settings: widget.settings,
              dragController: widget.dragController,
              badgeCounts: widget.badgeCounts,
              onAppTap: widget.onAppTap,
              onAppLongPress: (app, slot, center) => widget.onAppLongPress(app, i, slot, center),
            );
          },
        );
      },
    );
  }
}
