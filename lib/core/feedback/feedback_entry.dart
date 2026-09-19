import 'package:flutter/material.dart';
import 'package:genrevibes_feedback/genrevibes_feedback.dart';
import 'package:genrevibes_feedback_ui/genrevibes_feedback_ui.dart';
import 'package:smart_launcher_app/bootstrap/app_runtime.dart';
import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/analytics/app_events.dart';

/// Opens the shared feedback form, or falls back to an email draft.
///
/// The form is the kit's page with the launcher's delivery provider behind
/// it, so validation, the busy state, retry and the draft the user typed are
/// all handled there. If no FeedbackNest key is configured for this build the
/// provider is absent, and the caller is told so it can offer the mail app
/// instead of showing a dead button.
Future<bool> openLauncherFeedback(
  BuildContext context, {
  FeedbackKind kind = FeedbackKind.feedback,
}) async {
  final runtime = sl.isRegistered<AppRuntime>() ? sl<AppRuntime>() : null;
  final provider = runtime?.feedback;
  if (provider == null || !provider.health.isOperational) return false;
  AppAnalytics.event('feedback_opened', params: {'kind': kind.name});
  final sent = await openFeedbackPage(
    context,
    provider: provider,
    kind: kind,
    onSubmitted: (submission, result) => AppAnalytics.event(
      'feedback_submitted',
      params: {'kind': kind.name, 'succeeded': result.isSuccess},
    ),
  );
  return sent;
}
