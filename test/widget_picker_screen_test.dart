import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_launcher_app/models/launcher_settings.dart';
import 'package:smart_launcher_app/models/widget_provider_info.dart';
import 'package:smart_launcher_app/screens/settings/widget_picker_screen.dart';
import 'package:smart_launcher_app/services/widget_provider_cache_service.dart';
import 'package:smart_launcher_app/state/apps_cubit.dart';
import 'package:smart_launcher_app/state/settings_cubit.dart';
import 'package:smart_launcher_app/state/workspace_cubit.dart';

class _TestSettingsCubit extends SettingsCubit {
  _TestSettingsCubit(LauncherSettings initial) {
    emit(initial);
  }
}

class _TestAppsCubit extends AppsCubit {
  _TestAppsCubit() {
    emit(AppsState());
  }
}

class _TestWorkspaceCubit extends WorkspaceCubit {
  _TestWorkspaceCubit() {
    emit(WorkspaceState());
  }
}

Widget _wrap({required WidgetPickerScreen screen}) {
  return MaterialApp(
    home: MultiBlocProvider(
      providers: [
        BlocProvider<SettingsCubit>(
          create: (_) => _TestSettingsCubit(const LauncherSettings()),
        ),
        BlocProvider<AppsCubit>(create: (_) => _TestAppsCubit()),
        BlocProvider<WorkspaceCubit>(create: (_) => _TestWorkspaceCubit()),
      ],
      child: screen,
    ),
  );
}

// Advances the event loop a few frames so cache load + platform fetch
// microtasks resolve. Avoids pumpAndSettle which never returns while a
// CircularProgressIndicator / LinearProgressIndicator is on screen.
Future<void> _drain(WidgetTester tester) async {
  // Async cache load + platform fetch + setState + frame settle. The
  // CircularProgressIndicator ticker keeps pumpAndSettle from ever returning,
  // so we pump a fixed budget instead. runAsync lets real file I/O (the cache
  // load/save) complete; the surrounding pumps then process the resulting
  // setState calls.
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  late Directory tempDir;
  late WidgetProviderCacheService cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('widget_picker_test_');
    cache = WidgetProviderCacheService.forTesting(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  WidgetProviderInfo provider(String pkg, String label) => WidgetProviderInfo(
        packageName: pkg,
        appName: pkg,
        providerClass: '$pkg.W',
        label: label,
      );

  testWidgets('cold open shows spinner then platform results', (tester) async {
    final completer = Completer<List<WidgetProviderInfo>>();

    await tester.pumpWidget(_wrap(
      screen: WidgetPickerScreen(
        cacheService: cache,
        fetchWidgets: ({
          required gridColumns,
          required gridRows,
          required cellWidth,
          required cellHeight,
          required gap,
        }) =>
            completer.future,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete([provider('com.a', 'Alpha')]);
    await _drain(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('com.a'), findsOneWidget);
  });

  testWidgets('cache hit renders cached list before platform fetch resolves',
      (tester) async {
    // Step 1: prime the cache via a fast fetch.
    await tester.pumpWidget(_wrap(
      screen: WidgetPickerScreen(
        cacheService: cache,
        fetchWidgets: ({
          required gridColumns,
          required gridRows,
          required cellWidth,
          required cellHeight,
          required gap,
        }) async =>
            [provider('com.cached', 'Cached widget')],
      ),
    ));
    await _drain(tester);
    expect(find.text('com.cached'), findsOneWidget);

    // Step 2: open fresh picker with a hung platform call. The cached list
    // must surface before any platform data is returned.
    final hung = Completer<List<WidgetProviderInfo>>();
    await tester.pumpWidget(_wrap(
      screen: WidgetPickerScreen(
        cacheService: cache,
        fetchWidgets: ({
          required gridColumns,
          required gridRows,
          required cellWidth,
          required cellHeight,
          required gap,
        }) =>
            hung.future,
      ),
    ));
    await _drain(tester);

    expect(find.text('com.cached'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Cleanup: resolve the hung future so the test exits cleanly.
    hung.complete([provider('com.cached', 'Cached widget')]);
    await _drain(tester);
  });

  testWidgets('fresh platform data replaces stale cache contents',
      (tester) async {
    // Pre-seed the cache directly so we don't have to race the first
    // screen's fire-and-forget save.
    const key = WidgetCacheKey(
      gridColumns: 5,
      gridRows: 6,
      cellWidth: 152,
      cellHeight: 87,
    );
    // Use the picker's actual grid sig — easier to discover by snooping the
    // file the picker writes than to recompute here. Save under whatever
    // key the picker uses by piggybacking on a real bootstrap.
    await tester.pumpWidget(_wrap(
      screen: WidgetPickerScreen(
        cacheService: cache,
        fetchWidgets: ({
          required gridColumns,
          required gridRows,
          required cellWidth,
          required cellHeight,
          required gap,
        }) async =>
            [provider('com.stale', 'Stale')],
      ),
    ));
    await _drain(tester);
    expect(find.text('com.stale'), findsOneWidget);

    // Tear down the first screen completely before mounting the second.
    await tester.pumpWidget(const SizedBox.shrink());
    await _drain(tester);

    await tester.pumpWidget(_wrap(
      screen: WidgetPickerScreen(
        cacheService: cache,
        fetchWidgets: ({
          required gridColumns,
          required gridRows,
          required cellWidth,
          required cellHeight,
          required gap,
        }) async =>
            [provider('com.fresh', 'Fresh')],
      ),
    ));
    await _drain(tester);

    expect(find.text('com.fresh'), findsOneWidget);
    expect(find.text('com.stale'), findsNothing);
    expect(key.gridColumns, 5); // suppress unused warning
  });

  testWidgets('platform error with cache keeps cache visible', (tester) async {
    await tester.pumpWidget(_wrap(
      screen: WidgetPickerScreen(
        cacheService: cache,
        fetchWidgets: ({
          required gridColumns,
          required gridRows,
          required cellWidth,
          required cellHeight,
          required gap,
        }) async =>
            [provider('com.cached', 'Cached')],
      ),
    ));
    await _drain(tester);

    await tester.pumpWidget(_wrap(
      screen: WidgetPickerScreen(
        cacheService: cache,
        fetchWidgets: ({
          required gridColumns,
          required gridRows,
          required cellWidth,
          required cellHeight,
          required gap,
        }) async =>
            throw Exception('platform unavailable'),
      ),
    ));
    await _drain(tester);

    expect(find.text('com.cached'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });
}
