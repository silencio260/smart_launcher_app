import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_launcher_app/models/launcher_settings.dart';
import 'package:smart_launcher_app/state/workspace_cubit.dart';
import 'package:smart_launcher_app/widgets/edit_mode/edit_mode_overlay.dart';

class TestWorkspaceCubit extends WorkspaceCubit {
  TestWorkspaceCubit(WorkspaceState initialState) {
    emit(initialState);
  }
}

void main() {
  testWidgets('opens with the current page in focus', (tester) async {
    final cubit = TestWorkspaceCubit(
      WorkspaceState(
        currentPage: 2,
        pages: [
          WorkspacePage({}),
          WorkspacePage({}),
          WorkspacePage({}),
          WorkspacePage({}),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<WorkspaceCubit>.value(
          value: cubit,
          child: EditModeOverlay(
            settings: const LauncherSettings(),
            onDismiss: () {},
            onWallpaper: () {},
            onThemes: () {},
            onWidgets: () {},
            onSettings: () {},
            onPageSelected: cubit.setCurrentPage,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, greaterThan(0));
  });

  testWidgets('tapping a page card opens that page', (tester) async {
    final cubit = TestWorkspaceCubit(
      WorkspaceState(
        pages: [
          WorkspacePage({}),
          WorkspacePage({}),
        ],
      ),
    );
    var dismissed = false;
    int? selectedPage;

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<WorkspaceCubit>.value(
          value: cubit,
          child: EditModeOverlay(
            settings: const LauncherSettings(),
            onDismiss: () => dismissed = true,
            onWallpaper: () {},
            onThemes: () {},
            onWidgets: () {},
            onSettings: () {},
            onPageSelected: (page) {
              selectedPage = page;
              cubit.setCurrentPage(page);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cards = find.byKey(const ValueKey('edit-mode-page-card'));
    expect(cards, findsNWidgets(2));
    expect(
      find.descendant(of: cards.first, matching: find.byType(IgnorePointer)),
      findsOneWidget,
    );

    await tester.tap(cards.last);
    expect(selectedPage, 1);
    expect(cubit.state.currentPage, 1);

    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });
}
