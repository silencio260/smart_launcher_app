import 'package:flutter/material.dart';
import 'package:genrevibes_app_rating/genrevibes_app_rating.dart';
import 'package:smart_launcher_app/bootstrap/app_runtime.dart';
import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/analytics/app_events.dart';
import 'package:smart_launcher_app/core/feedback/feedback_entry.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/features/onboarding/data/onboarding_store.dart';

/// Asks for a store rating at a moment the launcher has actually earned one.
///
/// The app decides *when* it is reasonable to ask — onboarding finished, the
/// launcher is the user's real home screen, and they have come back on at
/// least three separate days — and the kit's [RatingCoordinator] decides
/// whether asking is *allowed*: install age, opens, snooze, and a previous
/// "never" all live there, so the prompt cannot nag.
abstract final class RatingPrompt {
  /// Days the user must have opened the launcher on before it asks.
  static const _minimumActiveDays = 3;

  static bool _askedThisProcess = false;

  /// Considers showing the prompt. Safe to call on every home-screen build;
  /// it asks at most once per process and only when every rule passes.
  static Future<void> maybeShow(BuildContext context) async {
    if (_askedThisProcess) return;
    if (!sl.isRegistered<AppRuntime>()) return;
    final runtime = sl<AppRuntime>();
    if (!runtime.rating.health.isOperational) return;
    if (!OnboardingStore.isCompletedSync) return;
    if (runtime.retention.snapshot.activeDays < _minimumActiveDays) return;
    if (!await LauncherService.isDefaultLauncher()) return;
    if (!context.mounted) return;

    final decision = await runtime.rating.evaluate();
    final allowed = decision.fold(
      onSuccess: (value) => value.isAllowed,
      onFailure: (_) => false,
    );
    if (!allowed || !context.mounted) return;
    _askedThisProcess = true;
    await runtime.rating.present(() => _present(context, runtime));
  }

  static Future<void> _present(BuildContext context, AppRuntime runtime) async {
    final enjoying = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enjoying Smart Launcher?'),
        content: const Text(
          'Tell us how it is going. It takes a moment and it decides what we '
          'work on next.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Could be better'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    AppAnalytics.event(
      'rating_prompt_answered',
      params: {
        'answer': switch (enjoying) {
          true => 'positive',
          false => 'negative',
          null => 'dismissed',
        },
      },
    );

    if (enjoying == null) {
      // Dismissed without answering: treat it as "later", never as declined.
      await runtime.rating.recordOutcome(RatingOutcome.maybeLater);
      return;
    }
    if (!enjoying) {
      // An unhappy user is routed to private feedback, not to the store.
      await runtime.rating.recordOutcome(RatingOutcome.maybeLater);
      if (!context.mounted) return;
      await openLauncherFeedback(context);
      return;
    }

    final followUp = await runtime.rating.recordOutcome(
      RatingOutcome.submitted,
    );
    final next = followUp.fold(
      onSuccess: (value) => value,
      onFailure: (_) => RatingFollowUp.none,
    );
    if (next != RatingFollowUp.storeReview) return;
    // A successful request does not prove Play showed anything, so nothing
    // here records that the user rated the app.
    final requested = await runtime.ratingStore.requestReview();
    requested.fold(
      onSuccess: (_) {},
      onFailure: (_) => runtime.ratingStore.openStoreListing(),
    );
  }
}
