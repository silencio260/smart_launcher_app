import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smart_launcher_app/core/analytics/app_events.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/features/onboarding/data/onboarding_store.dart';

part 'onboarding_state.dart';

/// Drives the first-run launcher onboarding: Welcome -> Search preview -> Style
/// picker -> Set as default (nudged, skippable) -> done. Mini-app setup is
/// intentionally NOT here; each mini-app onboards itself on first open.
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
      OnboardingStep.setDefault => 'set_default',
      OnboardingStep.done => 'done',
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

  void goToSetDefault() => _goTo(OnboardingStep.setDefault);

  void goToStyle() => _goTo(OnboardingStep.style);

  void backToStyle() => _goTo(OnboardingStep.style);

  void backToSearch() => _goTo(OnboardingStep.search);

  void backToWelcome() => _goTo(OnboardingStep.welcome);

  /// Opens the system home-role dialog. The actual grant is observed later via
  /// [refreshDefaultStatus] when the app resumes.
  Future<void> requestDefault() async {
    if (state.requestInFlight) return;
    emit(state.copyWith(requestInFlight: true));
    AppAnalytics.onboardingDefaultRequested();
    await LauncherService.requestHomeRole();
    emit(state.copyWith(requestInFlight: false));
  }

  /// Re-checks the home role. When it has just been granted, advances to the
  /// confirmation step. Returns the current default status.
  Future<bool> refreshDefaultStatus() async {
    final isDefault = await LauncherService.isDefaultLauncher();
    if (isDefault && !state.isDefaultLauncher) {
      AppAnalytics.launcherSetDefault(true);
    }
    emit(state.copyWith(
      isDefaultLauncher: isDefault,
      step: isDefault ? OnboardingStep.done : state.step,
    ));
    if (isDefault) _logPage(OnboardingStep.done);
    return isDefault;
  }

  /// Dev View preview only: jump to the confirmation screen without touching
  /// the real home role, so every screen can be inspected on a device that is
  /// already the default launcher.
  void markDoneForPreview() => _goTo(OnboardingStep.done);

  /// Persists completion and logs the outcome. [setDefault] reflects whether
  /// the launcher actually holds the home role at exit.
  Future<void> finish({required bool setDefault}) async {
    if (!setDefault) AppAnalytics.onboardingSkipped();
    AppAnalytics.onboardingCompleted(setDefault: setDefault);
    await OnboardingStore.markCompleted();
  }
}
