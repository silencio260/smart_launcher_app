import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_launcher_app/models/app_info.dart';
import 'package:smart_launcher_app/models/launcher_settings.dart';
import 'package:smart_launcher_app/services/drag/drag_controller.dart';
import 'package:smart_launcher_app/services/gestures/widget_resize_gesture_guard.dart';
import 'package:smart_launcher_app/state/apps_cubit.dart';
import 'package:smart_launcher_app/state/settings_cubit.dart';
import 'package:smart_launcher_app/state/workspace_cubit.dart';
import 'package:smart_launcher_app/widgets/dock/hotseat_view.dart';

void main() {
  tearDown(WidgetResizeGestureGuard.reset);

  testWidgets(
    'tapping a dock app dismisses widget selection without launching',
    (tester) async {
      var launchCount = 0;
      var dismissed = false;

      WidgetResizeGestureGuard.setSelectionActive(true);
      WidgetResizeGestureGuard.onRequestDismiss = () {
        dismissed = true;
        WidgetResizeGestureGuard.setSelectionActive(false);
      };

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<WorkspaceCubit>(create: (_) => WorkspaceCubit()),
              BlocProvider<AppsCubit>(create: (_) => AppsCubit()),
              BlocProvider<SettingsCubit>(create: (_) => SettingsCubit()),
            ],
            child: SizedBox(
              width: 320,
              height: 160,
              child: HotseatView(
                apps: [
                  DockAppItem(
                    AppInfo(
                      id: 1,
                      packageName: 'com.example.dock',
                      appComponentName: 'com.example.dock/.MainActivity',
                      title: 'Dock App',
                    ),
                  ),
                ],
                settings: const LauncherSettings(
                  dockSize: 1,
                  showDockLabels: true,
                ),
                dragController: DragController(),
                onSwipeUp: () {},
                onAppTap: (_) => launchCount += 1,
                onAppLongPress: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Dock App'));
      await tester.pump();

      expect(dismissed, isTrue);
      expect(launchCount, 0);

      await tester.tap(find.text('Dock App'));
      await tester.pump();
      expect(launchCount, 1);
    },
  );

  testWidgets('tapping an empty dock slot dismisses widget selection',
      (tester) async {
    var dismissed = false;

    WidgetResizeGestureGuard.setSelectionActive(true);
    WidgetResizeGestureGuard.onRequestDismiss = () {
      dismissed = true;
      WidgetResizeGestureGuard.setSelectionActive(false);
    };

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<WorkspaceCubit>(create: (_) => WorkspaceCubit()),
            BlocProvider<AppsCubit>(create: (_) => AppsCubit()),
            BlocProvider<SettingsCubit>(create: (_) => SettingsCubit()),
          ],
          child: SizedBox(
            width: 320,
            height: 160,
            child: HotseatView(
              apps: const [null, null],
              settings: const LauncherSettings(dockSize: 2),
              dragController: DragController(),
              onSwipeUp: () {},
              onAppTap: (_) {},
              onAppLongPress: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(240, 80));
    await tester.pump();

    expect(dismissed, isTrue);
    expect(WidgetResizeGestureGuard.isResizing, isFalse);
  });
}
