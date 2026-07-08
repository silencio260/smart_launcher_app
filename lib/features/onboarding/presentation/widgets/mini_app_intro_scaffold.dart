import 'package:flutter/material.dart';

import 'package:smart_launcher_app/core/analytics/app_events.dart';
import 'package:smart_launcher_app/core/widgets/mini_app_chrome.dart';

class MiniAppIntroSlide {
  final IconData icon;
  final String title;
  final String body;
  final String assetPath;

  const MiniAppIntroSlide({
    required this.icon,
    required this.title,
    required this.body,
    required this.assetPath,
  });
}

/// Shared first-open carousel for mini apps. The parent owns the one-shot
/// persistence flag; this widget only handles presentation and analytics.
class MiniAppCarouselScaffold extends StatefulWidget {
  const MiniAppCarouselScaffold({
    super.key,
    required this.featureId,
    required this.accent,
    required this.title,
    required this.slides,
    required this.ctaLabel,
    required this.onContinue,
    this.onBack,
  });

  final String featureId;
  final Color accent;
  final String title;
  final List<MiniAppIntroSlide> slides;
  final String ctaLabel;
  final VoidCallback onContinue;
  final VoidCallback? onBack;

  @override
  State<MiniAppCarouselScaffold> createState() =>
      _MiniAppCarouselScaffoldState();
}

class _MiniAppCarouselScaffoldState extends State<MiniAppCarouselScaffold> {
  final _controller = PageController();
  var _index = 0;

  @override
  void initState() {
    super.initState();
    AppAnalytics.miniAppOnboardingStarted(featureId: widget.featureId);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _skip() {
    AppAnalytics.miniAppOnboardingSkipped(featureId: widget.featureId);
    widget.onContinue();
  }

  void _next() {
    final last = _index == widget.slides.length - 1;
    if (last) {
      AppAnalytics.miniAppOnboardingCompleted(featureId: widget.featureId);
      widget.onContinue();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == widget.slides.length - 1;

    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: miniAppBackground,
        colorScheme: ThemeData.dark(useMaterial3: true)
            .colorScheme
            .copyWith(primary: widget.accent, surface: miniAppBackground),
      ),
      child: Scaffold(
        backgroundColor: miniAppBackground,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: widget.onBack ??
                            () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      Expanded(
                        child: Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _skip,
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: widget.slides.length,
                    onPageChanged: (index) => setState(() => _index = index),
                    itemBuilder: (context, index) {
                      final current = widget.slides[index];
                      return _MiniAppIntroSlideView(
                        slide: current,
                        accent: widget.accent,
                      );
                    },
                  ),
                ),
                _MiniAppDots(
                  count: widget.slides.length,
                  active: _index,
                  accent: widget.accent,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      isLast ? widget.ctaLabel : 'Continue',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniAppIntroSlideView extends StatelessWidget {
  const _MiniAppIntroSlideView({
    required this.slide,
    required this.accent,
  });

  final MiniAppIntroSlide slide;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageHeight =
            (constraints.maxHeight * 0.58).clamp(300.0, 520.0).toDouble();
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: imageHeight,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 28,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                slide.assetPath,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.medium,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(slide.icon, color: accent, size: 28),
            ),
            const SizedBox(height: 18),
            Text(
              slide.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              slide.body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: miniAppMuted,
                fontSize: 16,
                height: 1.35,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MiniAppDots extends StatelessWidget {
  const _MiniAppDots({
    required this.count,
    required this.active,
    required this.accent,
  });

  final int count;
  final int active;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Mini app onboarding step ${active + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (index) {
          final isActive = index == active;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: isActive ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive ? accent : Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}
