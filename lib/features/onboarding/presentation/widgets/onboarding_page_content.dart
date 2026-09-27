import 'package:flutter/material.dart';

import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/core/utils/app_strings.dart';

/// A launcher screenshot for an onboarding page's artwork.
class OnboardingScreenshot extends StatelessWidget {
  const OnboardingScreenshot({
    super.key,
    required this.assetPath,
    this.fullBleed = false,
  });

  final String assetPath;

  /// Fills the artwork area edge to edge (the kit's edge-to-edge layout)
  /// instead of a rounded, shadowed card.
  final bool fullBleed;

  @override
  Widget build(BuildContext context) {
    if (fullBleed) {
      return Image.asset(
        assetPath,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.medium,
      );
    }
    return Center(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 28,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

/// The style picker page's content. The flow supplies its controls.
class StylePickerContent extends StatelessWidget {
  const StylePickerContent({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final HomeMode selected;
  final ValueChanged<HomeMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.onboardingStyleTitle,
            textAlign: TextAlign.center,
            style: text.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.onboardingStyleBody,
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 28),
          _StyleOptionCard(
            mode: HomeMode.smart,
            selected: selected == HomeMode.smart,
            title: AppStrings.onboardingStyleSmart,
            body: AppStrings.onboardingStyleSmartBody,
            icon: Icons.auto_awesome_rounded,
            preview: const _SmartStylePreview(),
            onTap: onSelected,
          ),
          const SizedBox(height: 12),
          _StyleOptionCard(
            mode: HomeMode.ios,
            selected: selected == HomeMode.ios,
            title: AppStrings.onboardingStyleIos,
            body: AppStrings.onboardingStyleIosBody,
            icon: Icons.grid_view_rounded,
            preview: const _IosStylePreview(),
            onTap: onSelected,
          ),
          const SizedBox(height: 12),
          _StyleOptionCard(
            mode: HomeMode.minimal,
            selected: selected == HomeMode.minimal,
            title: AppStrings.onboardingStyleMinimal,
            body: AppStrings.onboardingStyleMinimalBody,
            icon: Icons.format_align_left_rounded,
            preview: const _MinimalStylePreview(),
            onTap: onSelected,
          ),
        ],
      ),
    );
  }
}

class _StyleOptionCard extends StatelessWidget {
  const _StyleOptionCard({
    required this.mode,
    required this.selected,
    required this.title,
    required this.body,
    required this.icon,
    required this.preview,
    required this.onTap,
  });

  final HomeMode mode;
  final bool selected;
  final String title;
  final String body;
  final IconData icon;
  final Widget preview;
  final ValueChanged<HomeMode> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedColor = scheme.inverseSurface;
    final borderColor = selected ? selectedColor : scheme.outlineVariant;

    return Material(
      color: selected
          ? scheme.surfaceContainerHighest
          : scheme.surfaceContainerHighest.withValues(alpha: 0.52),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(mode),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              SizedBox(width: 74, height: 68, child: preview),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 18, color: scheme.onSurface),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? selectedColor : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmartStylePreview extends StatelessWidget {
  const _SmartStylePreview();

  @override
  Widget build(BuildContext context) {
    return _PreviewShell(
      child: Column(
        children: [
          Row(
            children: const [
              _PreviewDot(width: 28),
              SizedBox(width: 6),
              _PreviewDot(width: 22),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(4, (_) => const _PreviewIcon()),
          ),
          const SizedBox(height: 8),
          const _PreviewPill(),
        ],
      ),
    );
  }
}

class _IosStylePreview extends StatelessWidget {
  const _IosStylePreview();

  @override
  Widget build(BuildContext context) {
    return _PreviewShell(
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 4.0;
          final iconSize =
              ((constraints.maxWidth - spacing * 3) / 4).clamp(8.0, 10.0);
          return Column(
            children: [
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: List.generate(
                  8,
                  (_) => _PreviewIcon(size: iconSize),
                ),
              ),
              const Spacer(),
              const _PreviewPill(),
            ],
          );
        },
      ),
    );
  }
}

class _MinimalStylePreview extends StatelessWidget {
  const _MinimalStylePreview();

  @override
  Widget build(BuildContext context) {
    return _PreviewShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _PreviewDot(width: 34),
          SizedBox(height: 10),
          _PreviewDot(width: 52),
          SizedBox(height: 7),
          _PreviewDot(width: 44),
          SizedBox(height: 7),
          _PreviewDot(width: 50),
        ],
      ),
    );
  }
}

class _PreviewShell extends StatelessWidget {
  const _PreviewShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }
}

class _PreviewIcon extends StatelessWidget {
  const _PreviewIcon({this.size = 13});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _PreviewDot extends StatelessWidget {
  const _PreviewDot({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 6,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _PreviewPill extends StatelessWidget {
  const _PreviewPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }
}
