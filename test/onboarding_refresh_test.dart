import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_launcher_app/config/theme_manager.dart';
import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/utils/app_strings.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/bloc/onboarding_cubit.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/widgets/mini_app_intro_scaffold.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await sl.reset();
    initApp();
  });

  testWidgets('launcher onboarding walks welcome, search, default, done',
      (tester) async {
    await _setPhoneViewport(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const OnboardingScreen(previewMode: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.onboardingWelcomeTitle), findsOneWidget);

    await tester.tap(find.text(AppStrings.onboardingGetStarted));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.onboardingSearchTitle), findsOneWidget);

    await tester.tap(find.text(AppStrings.onboardingContinue));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.onboardingDefaultTitle), findsOneWidget);

    await tester.tap(find.text(AppStrings.onboardingSetDefault));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.onboardingDoneTitle), findsOneWidget);
  });

  testWidgets('mini app carousel advances and completes on the last CTA',
      (tester) async {
    await _setPhoneViewport(tester);
    var continued = false;
    var backed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: MiniAppCarouselScaffold(
          featureId: 'test_feature',
          accent: Colors.blue,
          title: 'Test App',
          ctaLabel: 'Open Test App',
          onContinue: () => continued = true,
          onBack: () => backed = true,
          slides: const [
            MiniAppIntroSlide(
              icon: Icons.lock,
              title: 'First',
              body: 'First body',
              assetPath: 'assets/onboarding/app_lock_preview.png',
            ),
            MiniAppIntroSlide(
              icon: Icons.search,
              title: 'Second',
              body: 'Second body',
              assetPath: 'assets/onboarding/app_lock_preview.png',
            ),
            MiniAppIntroSlide(
              icon: Icons.check,
              title: 'Third',
              body: 'Third body',
              assetPath: 'assets/onboarding/app_lock_preview.png',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('First'), findsOneWidget);
    expect(find.text('Open Test App'), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Third'), findsOneWidget);
    expect(find.text('Open Test App'), findsOneWidget);

    await tester.tap(find.text('Open Test App'));
    await tester.pumpAndSettle();
    expect(continued, isTrue);
    expect(backed, isFalse);
  });

  testWidgets('mini app carousel skip continues, back does not',
      (tester) async {
    await _setPhoneViewport(tester);
    var continued = false;
    var backed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: MiniAppCarouselScaffold(
          featureId: 'test_feature',
          accent: Colors.blue,
          title: 'Test App',
          ctaLabel: 'Open Test App',
          onContinue: () => continued = true,
          onBack: () => backed = true,
          slides: const [
            MiniAppIntroSlide(
              icon: Icons.lock,
              title: 'Only',
              body: 'Only body',
              assetPath: 'assets/onboarding/app_lock_preview.png',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(continued, isTrue);
    expect(backed, isFalse);

    continued = false;
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(continued, isFalse);
    expect(backed, isTrue);
  });

  test('clock onboarding does not auto-request notification permission', () {
    final source =
        File('lib/features/clock/presentation/screens/alarm_clock_screen.dart')
            .readAsStringSync();

    expect(source, isNot(contains('_maybePromptNotifications')));
    expect(source, isNot(contains('_notificationPromptShown')));
  });

  test('onboarding finish keeps existing completion key behavior', () async {
    final cubit = OnboardingCubit();

    await cubit.finish(setDefault: false);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_completed_v1'), isTrue);
    await cubit.close();
  });
}

Future<void> _setPhoneViewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
