part of 'onboarding_cubit.dart';

/// The four visible steps of the launcher onboarding, plus the brief
/// success confirmation shown once the home role is granted.
enum OnboardingStep { welcome, search, style, setDefault, done }

class OnboardingState {
  final OnboardingStep step;

  /// Whether this app currently holds the system home role. Re-polled whenever
  /// the app resumes, since the grant happens in Android's own role dialog.
  final bool isDefaultLauncher;

  /// True while a `requestHomeRole` call is in flight (disables the CTA).
  final bool requestInFlight;

  const OnboardingState({
    required this.step,
    required this.isDefaultLauncher,
    required this.requestInFlight,
  });

  const OnboardingState.initial()
      : step = OnboardingStep.welcome,
        isDefaultLauncher = false,
        requestInFlight = false;

  OnboardingState copyWith({
    OnboardingStep? step,
    bool? isDefaultLauncher,
    bool? requestInFlight,
  }) =>
      OnboardingState(
        step: step ?? this.step,
        isDefaultLauncher: isDefaultLauncher ?? this.isDefaultLauncher,
        requestInFlight: requestInFlight ?? this.requestInFlight,
      );
}
