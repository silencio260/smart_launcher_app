import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smart_launcher_app/core/analytics/app_events.dart';
import 'package:smart_launcher_app/features/onboarding/data/onboarding_store.dart';

part 'onboarding_state.dart';

/// Drives the three onboarding screens: Welcome -> Search preview -> Style
/// picker. Set-as-default and wallpaper follow as separate screens (see
/// `setup_flow_screens.dart`). Mini-app setup is intentionally NOT here; each
/// mini-app onboards itself on first open.
class OnboardingCubit extends Cubit<OnboardingState> {
  OnboardingCubit() : super(const OnboardingState.initial());

  bool _startLogged = false;
  final _loggedPages = <OnboardingStep>{};

  /// Logged once when the flow first becomes visible.
  void start() {
    if (_startLogged) return;
    _startLogged = true;
    AppAnalytics.onboardingStarted();
    _logPage(OnboardingStep.welcome);
  }

  void _logPage(OnboardingStep step) {
    if (!_loggedPages.add(step)) return;
    final page = switch (step) {
      OnboardingStep.welcome => 'welcome',
      OnboardingStep.search => 'search',
      OnboardingStep.style => 'style',
    };
    AppAnalytics.onboardingPageViewed(page);
  }

  void _goTo(OnboardingStep step) {
    _logPage(step);
    emit(state.copyWith(step: step));
  }

  void pageChanged(OnboardingStep step) {
    if (step == state.step) return;
    _goTo(step);
  }

  void goToSearch() => _goTo(OnboardingStep.search);

  void goToStyle() => _goTo(OnboardingStep.style);

  void backToSearch() => _goTo(OnboardingStep.search);

  void backToWelcome() => _goTo(OnboardingStep.welcome);

  /// Persists that the three screens were seen. Completion analytics are
  /// logged once the set-as-default and wallpaper steps finish.
  Future<void> finish() => OnboardingStore.markCompleted();
}
