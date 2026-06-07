import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_launcher_app/core/models/app_info.dart';
import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/features/home/presentation/drag/drag_controller.dart';
import 'package:smart_launcher_app/features/home/presentation/gestures/widget_resize_gesture_guard.dart';
import 'package:smart_launcher_app/features/apps/presentation/bloc/apps_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:smart_launcher_app/features/home/presentation/bloc/workspace_cubit.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/dock/hotseat_view.dart';

void main() {
  tearDown(WidgetResizeGestureGuard.reset);

  testWidgets('long pressing a dock app reports its icon center',
      (tester) async {
    Offset? iconCenter;

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
              onAppTap: (_) {},
              onAppLongPress: (_, center) => iconCenter = center,
            ),
          ),
        ),
      ),
    );

    await tester.longPress(find.text('Dock App'));
    await tester.pump();

    expect(iconCenter, isNotNull);
    expect(iconCenter!.dx, greaterThan(0));
    expect(iconCenter!.dy, greaterThan(0));
  });

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
                onAppLongPress: (_, __) {},
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
              onAppLongPress: (_, __) {},
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
