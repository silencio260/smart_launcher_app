import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_launcher_app/models/launcher_widget_info.dart';
import 'package:smart_launcher_app/services/launcher_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const widgetsChannel = MethodChannel('com.genrevibes.smartlauncher/widgets');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(widgetsChannel, null);
  });

  test('getPlacedWidgetProviderMetadata sends only placed widget refs',
      () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(widgetsChannel, (call) async {
      capturedCall = call;
      return [
        {
          'packageName': 'com.example',
          'providerClass': 'ExampleWidget',
          'minWidth': 120,
          'minHeight': 80,
          'minResizeWidth': 100,
          'minResizeHeight': 60,
          'resizeMode': 3,
          'minSpanX': 1,
          'minSpanY': 1,
          'spanX': 2,
          'spanY': 1,
          'maxSpanX': 4,
          'maxSpanY': 3,
        }
      ];
    });

    final providers = await LauncherService.getPlacedWidgetProviderMetadata(
      widgets: [
        LauncherWidgetInfo(
          id: 42,
          appWidgetId: 42,
          providerPackage: 'com.example',
          providerClass: 'ExampleWidget',
        ),
      ],
      gridColumns: 4,
      gridRows: 5,
      cellWidth: 86,
      cellHeight: 148,
      gap: 8,
    );

    expect(capturedCall?.method, 'getPlacedWidgetProviderMetadata');
    expect(capturedCall?.arguments, isA<Map>());
    final args = capturedCall!.arguments as Map;
    expect(args['gridColumns'], 4);
    expect(args['gridRows'], 5);
    expect(args['cellWidth'], 86);
    expect(args['cellHeight'], 148);
    expect(args['gap'], 8);
    expect(args['widgets'], [
      {
        'appWidgetId': 42,
        'providerPackage': 'com.example',
        'providerClass': 'ExampleWidget',
      }
    ]);
    expect(providers, hasLength(1));
    expect(providers.single.packageName, 'com.example');
    expect(providers.single.providerClass, 'ExampleWidget');
    expect(providers.single.spanX, 2);
  });

  test('getAvailableWidgets still uses the full picker scan method', () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(widgetsChannel, (call) async {
      capturedCall = call;
      return <Map<String, Object?>>[];
    });

    await LauncherService.getAvailableWidgets(
      gridColumns: 4,
      gridRows: 5,
      cellWidth: 86,
      cellHeight: 148,
      gap: 8,
    );

    expect(capturedCall?.method, 'getAvailableWidgets');
  });
}
