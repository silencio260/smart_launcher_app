import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/features/home/presentation/screens/home_screen.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/bloc/onboarding_cubit.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/widgets/onboarding_done_page.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/widgets/set_default_page.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/widgets/welcome_page.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';

/// First-run launcher onboarding. Shown by the `MyApp` home gate when
/// onboarding hasn't completed; replaces itself with [HomeScreen] on finish.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, this.previewMode = false});

  /// When true (Dev View preview) the flow pops back to its launcher instead of
  /// replacing into [HomeScreen], and does not persist completion.
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

class _OnboardingViewState extends State<_OnboardingView>
    with WidgetsBindingObserver {
  final _pageController = PageController();
  bool _finishing = false;
  bool _doneScheduled = false;
  bool _programmaticPageChange = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.previewMode) return;
    // Catch the rare case where the role was already granted (e.g. set via
    // system, then app data cleared): skip straight to the confirmation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<OnboardingCubit>().refreshDefaultStatus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The home-role grant happens in Android's own dialog; re-poll on resume.
    if (state == AppLifecycleState.resumed && mounted && !widget.previewMode) {
      context.read<OnboardingCubit>().refreshDefaultStatus();
    }
  }

  int _indexFor(OnboardingStep step) => switch (step) {
        OnboardingStep.welcome => 0,
        OnboardingStep.search => 1,
        OnboardingStep.style => 2,
        OnboardingStep.setDefault => 3,
        OnboardingStep.done => 4,
      };

  Future<void> _finishToHome({required bool setDefault}) async {
    if (_finishing) return;
    _finishing = true;
    // Preview from Dev View: don't persist or replace the stack — just return.
    if (widget.previewMode) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    await context.read<OnboardingCubit>().finish(setDefault: setDefault);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen(firstRun: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return BlocConsumer<OnboardingCubit, OnboardingState>(
      listener: (context, state) {
        if (_pageController.hasClients) {
          _programmaticPageChange = true;
          _pageController
              .animateToPage(
                _indexFor(state.step),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              )
              .whenComplete(() => _programmaticPageChange = false);
        }
        if (state.step == OnboardingStep.done &&
            !_doneScheduled &&
            !widget.previewMode) {
          _doneScheduled = true;
          Future.delayed(const Duration(milliseconds: 1100), () {
            if (mounted) _finishToHome(setDefault: true);
          });
        }
      },
      builder: (context, state) {
        final cubit = context.read<OnboardingCubit>();
        return Scaffold(
          backgroundColor: scheme.surface,
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      if (_programmaticPageChange) return;
                      final step = _stepFor(index);
                      if (step == OnboardingStep.done) {
                        _pageController.jumpToPage(_indexFor(state.step));
                        return;
                      }
                      cubit.pageChanged(step);
                    },
                    children: [
                      WelcomePage(onGetStarted: cubit.goToSearch),
                      SearchPreviewPage(
                          onContinue: cubit.goToStyle,
                          onBack: cubit.backToWelcome),
                      BlocBuilder<SettingsCubit, LauncherSettings>(
                        buildWhen: (previous, next) =>
                            previous.homeMode != next.homeMode,
                        builder: (context, settings) {
                          return StylePickerPage(
                            selected: settings.homeMode,
                            onSelected: (mode) {
                              context.read<SettingsCubit>().update(
                                    settings.copyWith(homeMode: mode),
                                  );
                            },
                            onContinue: cubit.goToSetDefault,
                            onBack: cubit.backToSearch,
                          );
                        },
                      ),
                      SetDefaultPage(
                        requestInFlight: state.requestInFlight,
                        onSetDefault: widget.previewMode
                            ? cubit.markDoneForPreview
                            : cubit.requestDefault,
                        onNotNow: () => _finishToHome(setDefault: false),
                        onBack: cubit.backToStyle,
                      ),
                      const OnboardingDonePage(),
                    ],
                  ),
                ),
                _ProgressDots(step: state.step),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}

OnboardingStep _stepFor(int index) => switch (index) {
      0 => OnboardingStep.welcome,
      1 => OnboardingStep.search,
      2 => OnboardingStep.style,
      3 => OnboardingStep.setDefault,
      _ => OnboardingStep.done,
    };

/// Four-step progress indicator; hidden on the terminal confirmation.
class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.step});

  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    if (step == OnboardingStep.done) return const SizedBox(height: 8);
    final scheme = Theme.of(context).colorScheme;
    final active = switch (step) {
      OnboardingStep.welcome => 0,
      OnboardingStep.search => 1,
      OnboardingStep.style => 2,
      OnboardingStep.setDefault => 3,
      OnboardingStep.done => 3,
    };
    return Semantics(
      label: 'Onboarding step ${active + 1} of 4',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final isActive = i == active;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: isActive ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive ? scheme.onSurface : scheme.outlineVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}
