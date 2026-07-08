import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_launcher_app/core/models/launcher_feature.dart';
import 'package:smart_launcher_app/core/widgets/icons/feature_icon.dart';

void main() {
  test('clock uses the public Clock label', () {
    expect(LauncherFeatureCatalog.alarmClock.id, 'alarm_clock');
    expect(LauncherFeatureCatalog.alarmClock.title, 'Clock');
  });

  test('disguise aliases route to app hider but keep distinct artwork', () {
    const disguises = {
      LauncherFeatureCatalog.calculatorVaultClass: 'calculator',
      LauncherFeatureCatalog.notesVaultClass: 'notes',
      LauncherFeatureCatalog.weatherVaultClass: 'weather',
      LauncherFeatureCatalog.browserVaultClass: 'browser',
    };

    for (final entry in disguises.entries) {
      expect(LauncherFeatureCatalog.idForComponent(entry.key), 'app_hider');
      expect(
        LauncherFeatureCatalog.artworkForComponent(entry.key)?.id,
        entry.value,
      );
      expect(
        LauncherFeatureCatalog.artworkForComponent(
          '${LauncherFeature.launcherPackage}/${entry.key}',
        )?.id,
        entry.value,
      );
    }

    expect(
      disguises.keys
          .map((component) =>
              LauncherFeatureCatalog.artworkForComponent(component)?.id)
          .toSet(),
      hasLength(disguises.length),
    );
  });

  testWidgets('feature fallback icon uses PNG art instead of glyphs',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: FeatureIcon(
            featureId: 'alarm_clock',
            size: 56,
          ),
        ),
      ),
    );

    expect(find.byType(Icon), findsNothing);
    expect(
      find.descendant(
        of: find.byType(FeatureIcon),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
  });
}
