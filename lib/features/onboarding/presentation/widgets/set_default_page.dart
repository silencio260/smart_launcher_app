import 'dart:async';

import 'package:flutter/material.dart';

import 'package:smart_launcher_app/core/utils/app_strings.dart';

/// The home-role request shown after onboarding. There is no "Not now": the
/// close button only appears once the user has been to the system prompt and
/// come back without granting it (and never when the role is forced).
class SetDefaultPage extends StatefulWidget {
  const SetDefaultPage({
    super.key,
    required this.requestInFlight,
    required this.onSetDefault,
    this.showNotDefaultError = false,
    this.onClose,
  });

  final bool requestInFlight;
  final VoidCallback onSetDefault;

  /// Shown under the button after the user came back without granting it.
  final bool showNotDefaultError;
  final VoidCallback? onClose;

  @override
  State<SetDefaultPage> createState() => _SetDefaultPageState();
}

class _SetDefaultPageState extends State<SetDefaultPage> {
  Timer? _cancelTimer;
  bool _showCancel = false;
  int _errorGeneration = 0;

  bool get _canDismiss =>
      widget.showNotDefaultError &&
      !widget.requestInFlight &&
      widget.onClose != null;

  @override
  void initState() {
    super.initState();
    _scheduleCancel();
  }

  @override
  void didUpdateWidget(SetDefaultPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showNotDefaultError != widget.showNotDefaultError ||
        oldWidget.requestInFlight != widget.requestInFlight ||
        (oldWidget.onClose == null) != (widget.onClose == null)) {
      _scheduleCancel();
    }
  }

  void _scheduleCancel() {
    _cancelTimer?.cancel();
    _showCancel = false;
    final generation = ++_errorGeneration;
    if (!_canDismiss) return;
    // Start after the error's first rendered frame, not from the role request.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _errorGeneration || !_canDismiss) return;
      _cancelTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted || generation != _errorGeneration || !_canDismiss) return;
        setState(() => _showCancel = true);
      });
    });
  }

  @override
  void dispose() {
    _cancelTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 48,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IgnorePointer(
                        ignoring: !_showCancel || !_canDismiss,
                        child: ExcludeSemantics(
                          excluding: !_showCancel || !_canDismiss,
                          child: AnimatedOpacity(
                            opacity: _showCancel && _canDismiss ? 1 : 0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                            child: IconButton(
                              onPressed: _showCancel && _canDismiss
                                  ? widget.onClose
                                  : null,
                              // The reminder gate also renders above Navigator,
                              // where a tooltip has no Overlay ancestor.
                              icon: const Icon(
                                Icons.close_rounded,
                                semanticLabel: AppStrings.onboardingDefaultClose,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Center(
                    child: Container(
                      width: 148,
                      height: 148,
                      decoration: BoxDecoration(
                        color: scheme.inverseSurface,
                        borderRadius: BorderRadius.circular(36),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.18),
                            blurRadius: 40,
                            offset: const Offset(0, 22),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.home_rounded,
                        size: 76,
                        color: scheme.onInverseSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  Text(
                    AppStrings.onboardingDefaultTitle,
                    textAlign: TextAlign.center,
                    style: text.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    AppStrings.onboardingDefaultBody,
                    textAlign: TextAlign.center,
                    style: text.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.touch_app_outlined,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            AppStrings.onboardingDefaultHint,
                            style: text.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 2),
                  FilledButton(
                    onPressed: widget.requestInFlight
                        ? null
                        : widget.onSetDefault,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: widget.requestInFlight
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.onPrimary,
                            ),
                          )
                        : const Text(AppStrings.onboardingSetDefault),
                  ),
                  if (widget.showNotDefaultError)
                    Semantics(
                      liveRegion: true,
                      child: Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.error,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: scheme.onError,
                              size: 26,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppStrings.onboardingDefaultErrorTitle,
                                    style: text.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: scheme.onError,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    AppStrings.onboardingDefaultRequired,
                                    style: text.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      height: 1.4,
                                      color: scheme.onError,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
