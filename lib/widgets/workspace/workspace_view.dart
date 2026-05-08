import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/app_info.dart';
import '../../models/launcher_settings.dart';
import '../../services/drag/drag_controller.dart';
import '../../state/workspace_cubit.dart';
import '../smartspace/smartspace_view.dart';
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

  void _showClockMoveSheet(BuildContext context, WorkspaceState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ClockMoveSheet(
        currentClockPage: state.clockPage,
        totalPages: state.pages.length,
        onMove: (newPage) {
          context.read<WorkspaceCubit>().setClockPage(newPage);
          Navigator.pop(context);
        },
      ),
    );
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
            final cellLayout = CellLayoutView(
              page: state.pages[i],
              pageIndex: i,
              settings: widget.settings,
              dragController: widget.dragController,
              badgeCounts: widget.badgeCounts,
              onAppTap: widget.onAppTap,
              onAppLongPress: (app, slot, center) => widget.onAppLongPress(app, i, slot, center),
            );

            if (i == state.clockPage) {
              return Column(
                children: [
                  GestureDetector(
                    onLongPress: () => _showClockMoveSheet(context, state),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: SmartspaceView(settings: widget.settings),
                    ),
                  ),
                  Expanded(child: cellLayout),
                ],
              );
            }
            return cellLayout;
          },
        );
      },
    );
  }
}

class _ClockMoveSheet extends StatelessWidget {
  final int currentClockPage;
  final int totalPages;
  final void Function(int page) onMove;

  const _ClockMoveSheet({
    required this.currentClockPage,
    required this.totalPages,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900]!.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Move clock to page',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          ...List.generate(totalPages, (i) {
            final isCurrent = i == currentClockPage;
            return ListTile(
              leading: Icon(
                isCurrent ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: isCurrent ? Colors.white : Colors.white54,
              ),
              title: Text(
                'Page ${i + 1}',
                style: TextStyle(
                  color: isCurrent ? Colors.white : Colors.white70,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              onTap: isCurrent ? null : () => onMove(i),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
