import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_launcher_app/main.dart';

void main() {
  testWidgets('launcher app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartLauncherApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
