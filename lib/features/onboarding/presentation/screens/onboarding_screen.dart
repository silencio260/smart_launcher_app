import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/bloc/onboarding_cubit.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/screens/setup_flow_screens.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/widgets/welcome_page.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';

/// First-run launcher onboarding: three screens. Shown by the `MyApp` home
/// gate when onboarding hasn't completed; replaces itself with
/// [SetDefaultScreen] on finish.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, this.previewMode = false});

  /// When true (Dev View preview) the flow returns to its launcher at the end
  /// instead of opening Home, and does not persist completion.
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
  final _pageController = PageController();
  bool _finishing = false;
  bool _programmaticPageChange = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    if (!widget.previewMode) await context.read<OnboardingCubit>().finish();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SetDefaultScreen(previewMode: widget.previewMode),
      ),
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
                state.step.index,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              )
              .whenComplete(() => _programmaticPageChange = false);
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
                      cubit.pageChanged(OnboardingStep.values[index]);
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
                            onContinue: _finish,
                            onBack: cubit.backToSearch,
                          );
                        },
                      ),
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

/// One dot per onboarding screen.
class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.step});

  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = OnboardingStep.values.length;
    final active = step.index;
    return Semantics(
      label: 'Onboarding step ${active + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
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
