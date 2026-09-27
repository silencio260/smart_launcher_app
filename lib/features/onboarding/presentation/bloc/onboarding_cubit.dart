import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smart_launcher_app/core/analytics/app_events.dart';

part 'onboarding_state.dart';

/// Onboarding analytics for the three screens: Welcome -> Search preview ->
/// Style picker. Paging, finishing and completion belong to the kit's
/// `OnboardingFlow` and `OnboardingController`; set-as-default and wallpaper
/// follow as separate screens. Mini-app setup is intentionally NOT here; each
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
  }

  /// Records the visible page; each page's view is logged once.
  void pageChanged(int index) {
    final step = OnboardingStep.values[index];
    if (_loggedPages.add(step)) {
      AppAnalytics.onboardingPageViewed(switch (step) {
        OnboardingStep.welcome => 'welcome',
        OnboardingStep.search => 'search',
        OnboardingStep.style => 'style',
      });
    }
    emit(state.copyWith(step: step));
  }
}
