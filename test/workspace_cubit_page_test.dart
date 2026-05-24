import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
}
