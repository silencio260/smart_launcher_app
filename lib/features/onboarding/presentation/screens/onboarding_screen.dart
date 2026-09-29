import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:genrevibes_onboarding/genrevibes_onboarding.dart';

import 'package:smart_launcher_app/bootstrap/app_runtime.dart';
import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/ads/launcher_ads.dart';
import 'package:smart_launcher_app/core/ads/launcher_native_ad.dart';
import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/core/utils/app_strings.dart';
import 'package:smart_launcher_app/features/onboarding/data/onboarding_store.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/bloc/onboarding_cubit.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/screens/setup_flow_screens.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/widgets/onboarding_page_content.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';

/// First-run launcher onboarding: three screens on the kit's
/// [OnboardingFlow], with completion in the runtime's [OnboardingController].
/// Shown by the `MyApp` home gate when onboarding hasn't completed; replaces
/// itself with [SetDefaultScreen] on finish.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, this.previewMode = false});

  /// When true (Dev View preview) the flow continues into setup without
  /// persisting completion, and setup returns to its launcher at the end.
  final bool previewMode;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<OnboardingCubit>(
      create: (_) => sl<OnboardingCubit>()..start(),
      child: _OnboardingView(previewMode: previewMode),
    );
  }
}

class _OnboardingView extends StatefulWidget {
  const _OnboardingView({required this.previewMode});

  final bool previewMode;

  @override
  State<_OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<_OnboardingView> {
  // Decided once, so a screen's layout doesn't change under the user.
  final bool _adAllowed = LauncherAds.onboardingAdAllowed;

  void _openSetup(BuildContext context) {
    unawaited(LauncherAds.prepareInlineAds());
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SetDefaultScreen(previewMode: widget.previewMode),
      ),
    );
  }

  List<OnboardingAction> get _finishActions => [
    if (!widget.previewMode) ...[
      // Stops the sequence if the flag can't be written; the user can
      // retry instead of being onboarded in memory only.
      OnboardingAction.markCompleted(sl<AppRuntime>().onboarding),
      OnboardingAction(
        (_) => OnboardingStore.markSetupPending(),
        name: 'mark_setup_pending',
        continueOnError: true,
      ),
    ],
    OnboardingAction(_openSetup, name: 'open_setup'),
  ];

  /// The native ad's own height (see [LauncherNativeAd]), so the ad screen is
  /// laid out with it from the first frame and nothing moves when it loads.
  double _adHeight(BuildContext context) =>
      LauncherNativeAd.reservedHeight(context);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final cubit = context.read<OnboardingCubit>();

    return Scaffold(
      backgroundColor: scheme.surface,
      body: OnboardingFlow(
        pages: [
          OnboardingPage(
            title: AppStrings.onboardingWelcomeTitle,
            description: AppStrings.onboardingWelcomeBody,
            artwork: (_) => const OnboardingScreenshot(
              assetPath: 'assets/onboarding/launcher_home_preview.webp',
            ),
            showAd: false,
          ),
          // The one ad screen, between two full-screen ones. Edge to edge:
          // the screenshot takes the top half above the ad, or most of the
          // screen when no ad slot is laid out.
          OnboardingPage(
            title: AppStrings.onboardingSearchTitle,
            description: AppStrings.onboardingSearchBody,
            layout: OnboardingScreenLayout.edgeToEdge,
            artwork: (_) => const OnboardingScreenshot(
              assetPath: 'assets/onboarding/launcher_search_preview.webp',
              fullBleed: true,
            ),
          ),
          OnboardingPage(
            title: AppStrings.onboardingStyleTitle,
            description: AppStrings.onboardingStyleBody,
            template: OnboardingTemplate.custom,
            showAd: false,
            artwork: (_) => BlocBuilder<SettingsCubit, LauncherSettings>(
              buildWhen: (previous, next) => previous.homeMode != next.homeMode,
              builder: (context, settings) => StylePickerContent(
                selected: settings.homeMode,
                onSelected: (mode) => context.read<SettingsCubit>().update(
                  settings.copyWith(homeMode: mode),
                ),
              ),
            ),
          ),
        ],
        controlsLayout: OnboardingControlsLayout.fullWidthButton,
        skipBehavior: OnboardingSkipBehavior.hidden,
        labels: const OnboardingLabels(
          next: AppStrings.onboardingContinue,
          finish: AppStrings.onboardingContinue,
        ),
        adSlot: _adAllowed
            ? OnboardingAdSlot(
                reservedHeight: _adHeight(context),
                builder: (_, __) => const _OnboardingAd(),
              )
            : null,
        finishActions: _finishActions,
        onPageChanged: cubit.pageChanged,
        onActionError: (action, error, _) {
          if (action.name != 'mark_completed' || !mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Couldn't save your progress. Please try again."),
            ),
          );
        },
        style: OnboardingFlowStyle(
          backgroundColor: scheme.surface,
          titleStyle: text.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: scheme.onSurface,
          ),
          descriptionStyle: text.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.35,
          ),
          activeIndicatorColor: scheme.onSurface,
          inactiveIndicatorColor: scheme.outlineVariant,
          buttonStyle: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          pagePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          artworkFadeHeight: 48,
        ),
      ),
    );
  }
}

/// The ad screen's slot: a placeholder card the size of the native ad, with
/// the ad drawn over it once one loads.
class _OnboardingAd extends StatelessWidget {
  const _OnboardingAd();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12, 6, 12, 2),
                    child: Text(
                      'Ad',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const LauncherNativeAd(
            placement: LauncherAdPlacements.onboardingNative,
          ),
        ],
      ),
    );
  }
}
