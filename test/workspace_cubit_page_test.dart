import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_launcher_app/models/launcher_widget_info.dart';
import 'package:smart_launcher_app/state/workspace_cubit.dart';

class TestWorkspaceCubit extends WorkspaceCubit {
  TestWorkspaceCubit(WorkspaceState initialState) {
    emit(initialState);
  }
}

void main() {
  test('setCurrentPage clamps to existing workspace pages', () async {
    final cubit = TestWorkspaceCubit(
      WorkspaceState(
        pages: [
          WorkspacePage({}),
          WorkspacePage({}),
        ],
      ),
    );

    cubit.setCurrentPage(99);
    expect(cubit.state.currentPage, 1);

    cubit.setCurrentPage(-5);
    expect(cubit.state.currentPage, 0);

    await cubit.close();
  });

  test('loadLayout clamps a stale restored currentPage', () async {
    SharedPreferences.setMockInitialValues({
      'workspace_layout_v1': jsonEncode({
        'currentPage': 99,
        'pages': [
          {'slots': <String, Object?>{}},
          {'slots': <String, Object?>{}},
        ],
      }),
    });

    final cubit = WorkspaceCubit();
    await cubit.loadLayout();

    expect(cubit.state.pages.length, 2);
    expect(cubit.state.currentPage, 1);

    await cubit.close();
  });

  test('addWidgetToStackSlot keeps existing stack size', () async {
    final existing = LauncherWidgetInfo(
      id: 1,
      appWidgetId: 1,
      providerPackage: 'existing',
      providerClass: 'ExistingWidget',
      spanX: 2,
      spanY: 2,
    );
    final picked = LauncherWidgetInfo(
      id: 2,
      appWidgetId: 2,
      providerPackage: 'picked',
      providerClass: 'PickedWidget',
      spanX: 4,
      spanY: 3,
      minSpanX: 4,
      minSpanY: 3,
    );
    final cubit = TestWorkspaceCubit(
      WorkspaceState(
        pages: [
          WorkspacePage({
            0: WidgetStackSlot([existing], spanX: 2, spanY: 2),
          }),
        ],
      ),
    );

    cubit.addWidgetToStackSlot(0, 0, picked);

    final stack = cubit.state.pages.single.slots[0] as WidgetStackSlot;
    expect(stack.spanX, 2);
    expect(stack.spanY, 2);
    expect(stack.widgets.last.spanX, 2);
    expect(stack.widgets.last.spanY, 2);
    expect(stack.currentIndex, 1);

    await cubit.close();
  });

  test('addWidgetToStackSlot converts a single widget at its current size',
      () async {
    final existing = LauncherWidgetInfo(
      id: 1,
      appWidgetId: 1,
      providerPackage: 'existing',
      providerClass: 'ExistingWidget',
      spanX: 3,
      spanY: 1,
    );
    final picked = LauncherWidgetInfo(
      id: 2,
      appWidgetId: 2,
      providerPackage: 'picked',
      providerClass: 'PickedWidget',
      spanX: 5,
      spanY: 4,
    );
    final cubit = TestWorkspaceCubit(
      WorkspaceState(
        pages: [
          WorkspacePage({0: WidgetSlot(existing)}),
        ],
      ),
    );

    cubit.addWidgetToStackSlot(0, 0, picked);

    final stack = cubit.state.pages.single.slots[0] as WidgetStackSlot;
    expect(stack.spanX, 3);
    expect(stack.spanY, 1);
    expect(stack.widgets.map((widget) => widget.spanX), [3, 3]);
    expect(stack.widgets.map((widget) => widget.spanY), [1, 1]);
    expect(stack.currentIndex, 1);

    await cubit.close();
  });

  test('removeWidgetFromStack can keep a one-widget stack for edit mode',
      () async {
    final first = LauncherWidgetInfo(
      id: 1,
      appWidgetId: 1,
      providerPackage: 'first',
      providerClass: 'FirstWidget',
    );
    final second = LauncherWidgetInfo(
      id: 2,
      appWidgetId: 2,
      providerPackage: 'second',
      providerClass: 'SecondWidget',
    );
    final cubit = TestWorkspaceCubit(
      WorkspaceState(
        pages: [
          WorkspacePage({
            0: WidgetStackSlot(
              [first, second],
              spanX: 2,
              spanY: 2,
              currentIndex: 1,
            ),
          }),
        ],
      ),
    );

    cubit.removeWidgetFromStack(0, 0, 1, collapseSingle: false);

    final stack = cubit.state.pages.single.slots[0] as WidgetStackSlot;
    expect(stack.widgets, [first]);
    expect(stack.currentIndex, 0);

    await cubit.close();
  });

  test('updateWidgetStackIndex persists the focused stack widget', () async {
    final widgets = List.generate(
      3,
      (index) => LauncherWidgetInfo(
        id: index + 1,
        appWidgetId: index + 1,
        providerPackage: 'pkg$index',
        providerClass: 'Widget$index',
      ),
    );
    final cubit = TestWorkspaceCubit(
      WorkspaceState(
        pages: [
          WorkspacePage({
            0: WidgetStackSlot(widgets, spanX: 2, spanY: 2),
          }),
        ],
      ),
    );

    cubit.updateWidgetStackIndex(0, 0, 2);

    final stack = cubit.state.pages.single.slots[0] as WidgetStackSlot;
    expect(stack.currentIndex, 2);

    await cubit.close();
  });
}
