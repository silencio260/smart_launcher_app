import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_launcher_app/core/models/app_info.dart';
import 'package:smart_launcher_app/core/models/item_info.dart';
import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/core/models/workspace_item_info.dart';
import 'package:smart_launcher_app/features/apps/presentation/bloc/apps_cubit.dart';
import 'package:smart_launcher_app/features/home/presentation/bloc/workspace_cubit.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/edit_mode/edit_mode_overlay.dart';
import 'package:smart_launcher_app/core/widgets/icons/shaped_icon.dart';

class TestWorkspaceCubit extends WorkspaceCubit {
  TestWorkspaceCubit(WorkspaceState initialState) {
    emit(initialState);
  }
}

class TestAppsCubit extends AppsCubit {
  TestAppsCubit(AppsState initialState) {
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
        home: MultiBlocProvider(
          providers: [
            BlocProvider<WorkspaceCubit>.value(value: cubit),
            BlocProvider<AppsCubit>(
              create: (_) => TestAppsCubit(AppsState()),
            ),
          ],
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
        home: MultiBlocProvider(
          providers: [
            BlocProvider<WorkspaceCubit>.value(value: cubit),
            BlocProvider<AppsCubit>(
              create: (_) => TestAppsCubit(AppsState()),
            ),
          ],
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

  testWidgets('page preview resolves app icons from live apps', (tester) async {
    final liveIcon = Uint8List.fromList([1, 2, 3, 4]);
    final cubit = TestWorkspaceCubit(
      WorkspaceState(
        pages: [
          WorkspacePage({
            0: AppSlot(
              WorkspaceItemInfo(
                id: 1,
                itemType: ItemType.application,
                packageName: 'com.example.live',
                componentName: 'com.example.live/.MainActivity',
                title: 'Stored',
              ),
            ),
          }),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<WorkspaceCubit>.value(value: cubit),
            BlocProvider<AppsCubit>(
              create: (_) => TestAppsCubit(
                AppsState(
                  apps: [
                    AppInfo(
                      id: 1,
                      packageName: 'com.example.live',
                      appComponentName: 'com.example.live/.MainActivity',
                      title: 'Live',
                      icon: liveIcon,
                    ),
                  ],
                ),
              ),
            ),
          ],
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

    final shapedIcon = tester.widget<ShapedIcon>(find.byType(ShapedIcon));
    expect(shapedIcon.iconBytes, same(liveIcon));
    expect(shapedIcon.cacheKey, 'com.example.live');
  });
}
