part of 'onboarding_cubit.dart';

/// The three onboarding screens. Set-as-default and wallpaper come after
/// onboarding (see `setup_flow_screens.dart`).
enum OnboardingStep { welcome, search, style }

class OnboardingState {
  final OnboardingStep step;

  const OnboardingState({required this.step});

  const OnboardingState.initial() : step = OnboardingStep.welcome;

  OnboardingState copyWith({OnboardingStep? step}) =>
      OnboardingState(step: step ?? this.step);
}
