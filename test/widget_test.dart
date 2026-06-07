import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/my_app.dart';

void main() {
  testWidgets('launcher app builds', (WidgetTester tester) async {
    // MyApp resolves its app-wide cubits from the GetIt service locator.
    await sl.reset();
    initApp();

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
