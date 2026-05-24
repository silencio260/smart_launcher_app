import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_launcher_app/models/item_info.dart';
import 'package:smart_launcher_app/models/launcher_settings.dart';
import 'package:smart_launcher_app/models/launcher_widget_info.dart';
import 'package:smart_launcher_app/models/workspace_item_info.dart';
import 'package:smart_launcher_app/services/drag/drag_controller.dart';
import 'package:smart_launcher_app/services/gestures/widget_resize_gesture_guard.dart';
import 'package:smart_launcher_app/state/apps_cubit.dart';
import 'package:smart_launcher_app/state/settings_cubit.dart';
import 'package:smart_launcher_app/state/workspace_cubit.dart';
import 'package:smart_launcher_app/widgets/workspace/cell_layout.dart';
import 'package:smart_launcher_app/widgets/workspace/home_widget_slot.dart';

class TestWorkspaceCubit extends WorkspaceCubit {
  TestWorkspaceCubit(WorkspaceState initialState) {
    emit(initialState);
  }
}

void main() {
  tearDown(WidgetResizeGestureGuard.reset);

  testWidgets(
    'long pressing empty space opens edit menu while widget is selected',
    (tester) async {
      final widgetInfo = LauncherWidgetInfo(
        id: 1,
        appWidgetId: 1,
        providerPackage: WorkspaceCubit.defaultClockProviderPackage,
        providerClass: WorkspaceCubit.defaultClockProviderClass,
        isCustomWidget: true,
        spanX: 1,
        spanY: 1,
      );
      final workspace = TestWorkspaceCubit(
        WorkspaceState(
          pages: [
            WorkspacePage({0: WidgetSlot(widgetInfo)}),
          ],
        ),
      );
      var menuOpened = false;

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<WorkspaceCubit>.value(value: workspace),
              BlocProvider<AppsCubit>(create: (_) => AppsCubit()),
              BlocProvider<SettingsCubit>(create: (_) => SettingsCubit()),
            ],
            child: SizedBox(
              width: 400,
              height: 600,
              child: CellLayoutView(
                page: workspace.state.pages.first,
                pageIndex: 0,
                settings: const LauncherSettings(
                  gridColumns: 4,
                  gridRows: 4,
                ),
                dragController: DragController(),
                onAppTap: (_) {},
                onAppLongPress: (_, __, ___) {},
                onBackgroundLongPress: () => menuOpened = true,
              ),
            ),
          ),
        ),
      );

      await tester.longPress(find.byType(HomeWidgetSlot));
      await tester.pump();
      expect(WidgetResizeGestureGuard.isResizing, isTrue);

      await tester.longPressAt(const Offset(360, 540));
      await tester.pump();

      expect(menuOpened, isTrue);
      expect(WidgetResizeGestureGuard.isResizing, isFalse);
    },
  );

  testWidgets(
    'tapping a home app dismisses widget selection without launching',
    (tester) async {
      final widgetInfo = LauncherWidgetInfo(
        id: 1,
        appWidgetId: 1,
        providerPackage: WorkspaceCubit.defaultClockProviderPackage,
        providerClass: WorkspaceCubit.defaultClockProviderClass,
        isCustomWidget: true,
        spanX: 1,
        spanY: 1,
      );
      final appItem = WorkspaceItemInfo(
        id: 2,
        itemType: ItemType.application,
        packageName: 'com.example.app',
        componentName: 'com.example.app/.MainActivity',
        title: 'Example App',
      );
      final workspace = TestWorkspaceCubit(
        WorkspaceState(
          pages: [
            WorkspacePage({
              0: WidgetSlot(widgetInfo),
              5: AppSlot(appItem),
            }),
          ],
        ),
      );
      var launchCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<WorkspaceCubit>.value(value: workspace),
              BlocProvider<AppsCubit>(create: (_) => AppsCubit()),
              BlocProvider<SettingsCubit>(create: (_) => SettingsCubit()),
            ],
            child: SizedBox(
              width: 400,
              height: 600,
              child: CellLayoutView(
                page: workspace.state.pages.first,
                pageIndex: 0,
                settings: const LauncherSettings(
                  gridColumns: 4,
                  gridRows: 4,
                ),
                dragController: DragController(),
                onAppTap: (_) => launchCount += 1,
                onAppLongPress: (_, __, ___) {},
                onBackgroundLongPress: () {},
              ),
            ),
          ),
        ),
      );

      await tester.longPress(find.byType(HomeWidgetSlot));
      await tester.pump();
      expect(WidgetResizeGestureGuard.isResizing, isTrue);

      await tester.tap(find.text('Example App'));
      await tester.pump();

      expect(launchCount, 0);
      expect(WidgetResizeGestureGuard.isResizing, isFalse);

      await tester.tap(find.text('Example App'));
      await tester.pump();
      expect(launchCount, 1);

      await tester.pump(const Duration(milliseconds: 400));
    },
  );
}
