import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_launcher_app/models/widget_provider_info.dart';
import 'package:smart_launcher_app/services/widget_provider_cache_service.dart';

void main() {
  late Directory tempDir;
  late WidgetProviderCacheService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('widget_cache_test_');
    service = WidgetProviderCacheService.forTesting(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  const key = WidgetCacheKey(
    gridColumns: 5,
    gridRows: 6,
    cellWidth: 72,
    cellHeight: 88,
  );

  test('returns null when no cache file exists', () async {
    final loaded = await service.load(key);
    expect(loaded, isNull);
  });

  test('round-trips providers with byte payloads', () async {
    final iconBytes = Uint8List.fromList([0xAB, 0xCD, 0xEF, 0x01]);
    final previewBytes =
        Uint8List.fromList(List<int>.generate(2048, (i) => i & 0xFF));
    final providers = [
      WidgetProviderInfo(
        packageName: 'com.example.one',
        appName: 'Example One',
        providerClass: 'com.example.one.Widget',
        label: 'First widget',
        minWidth: 100,
        minHeight: 200,
        minResizeWidth: 80,
        minResizeHeight: 80,
        maxResizeWidth: 400,
        maxResizeHeight: 400,
        resizeMode: 3,
        targetCellWidth: 2,
        targetCellHeight: 1,
        minSpanX: 1,
        minSpanY: 1,
        spanX: 2,
        spanY: 1,
        maxSpanX: 5,
        maxSpanY: 3,
        appIcon: iconBytes,
        previewImage: previewBytes,
        previewIsGenerated: true,
      ),
      const WidgetProviderInfo(
        packageName: 'com.example.two',
        appName: 'Example Two',
        providerClass: 'com.example.two.W',
        label: 'No icon widget',
      ),
    ];

    await service.save(key, providers);
    final loaded = await service.load(key);

    expect(loaded, isNotNull);
    expect(loaded!.length, 2);

    final a = loaded[0];
    expect(a.packageName, 'com.example.one');
    expect(a.appName, 'Example One');
    expect(a.providerClass, 'com.example.one.Widget');
    expect(a.label, 'First widget');
    expect(a.minWidth, 100);
    expect(a.minHeight, 200);
    expect(a.targetCellWidth, 2);
    expect(a.spanX, 2);
    expect(a.maxSpanY, 3);
    expect(a.previewIsGenerated, isTrue);
    expect(a.appIcon, isNotNull);
    expect(a.appIcon!.length, iconBytes.length);
    for (var i = 0; i < iconBytes.length; i++) {
      expect(a.appIcon![i], iconBytes[i]);
    }
    expect(a.previewImage, isNotNull);
    expect(a.previewImage!.length, previewBytes.length);
    for (var i = 0; i < previewBytes.length; i += 137) {
      expect(a.previewImage![i], previewBytes[i]);
    }

    final b = loaded[1];
    expect(b.packageName, 'com.example.two');
    expect(b.appIcon, isNull);
    expect(b.previewImage, isNull);
    expect(b.previewIsGenerated, isFalse);
  });

  test('returns null when grid key mismatches', () async {
    await service.save(key, [
      const WidgetProviderInfo(
        packageName: 'a',
        appName: 'A',
        providerClass: 'a.A',
        label: 'a',
      ),
    ]);

    final other = const WidgetCacheKey(
      gridColumns: 4,
      gridRows: 6,
      cellWidth: 72,
      cellHeight: 88,
    );
    expect(await service.load(other), isNull);

    // Same key still returns the cached entry.
    expect(await service.load(key), isNotNull);
  });

  test('clear deletes the cache file', () async {
    await service.save(key, [
      const WidgetProviderInfo(
        packageName: 'a',
        appName: 'A',
        providerClass: 'a.A',
        label: 'a',
      ),
    ]);
    expect(await service.load(key), isNotNull);

    await service.clear();
    expect(await service.load(key), isNull);
  });

  test('handles unicode strings', () async {
    final providers = [
      const WidgetProviderInfo(
        packageName: 'com.example.unicode',
        appName: '日本語アプリ',
        providerClass: 'com.example.W',
        label: 'Widget 🎨 with emoji',
      ),
    ];
    await service.save(key, providers);
    final loaded = await service.load(key);
    expect(loaded, isNotNull);
    expect(loaded!.first.appName, '日本語アプリ');
    expect(loaded.first.label, 'Widget 🎨 with emoji');
  });
}
