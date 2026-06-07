import 'package:flutter/material.dart';

import 'package:smart_launcher_app/core/models/launcher_feature.dart';
import 'package:smart_launcher_app/core/widgets/icons/feature_icon.dart';
import 'package:smart_launcher_app/core/widgets/mini_app_chrome.dart';

/// Shared design kit for the privacy mini-apps (App Locker, App Hider, File
/// Vault). It mirrors the One UI patterns the clock app uses (see
/// `clock/clock_theme.dart`) but parameterises the accent so each feature keeps
/// its own brand colour (red / indigo / teal) without touching the shared
/// orange baked into [MiniAppScaffold].
///
/// Reuse-first: branded icons come from [FeatureIcon], neutral surfaces from
/// [mini_app_chrome.dart]. Nothing here mutates the global theme constants.

/// The accent for a feature, single-sourced from the launcher catalog
/// (`file_locker` teal, `app_hider` indigo, `app_locker` red). Falls back to
/// the shared orange for unknown ids.
Color accentForFeature(String featureId) =>
    LauncherFeatureCatalog.fromId(featureId)?.color ?? miniAppAccent;

/// Wraps the ambient theme so in-app selection states and switches render in
/// [accent] instead of the shared orange. Apply with a [Theme] around the
/// screen body, exactly like `clockThemeOf` does for the clock.
ThemeData miniAppThemeOf(BuildContext context, Color accent) {
  final base = Theme.of(context);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(primary: accent),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? Colors.white : miniAppMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? accent : miniAppSurface2,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
  );
}

/// A rounded dark surface card (radius 20), the building block of the redesign.
/// Softer than the shared 8px [MiniCard] to match the reference vault.
class RoundCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;

  const RoundCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(18),
    this.color = miniAppSurface,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: card,
      ),
    );
  }
}

/// Top-of-screen identity header: the branded [FeatureIcon], a title, and a
/// one-line status/subtitle. Replaces the ad-hoc circle-icon headers each
/// screen had.
class MiniHeroCard extends StatelessWidget {
  final String featureId;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const MiniHeroCard({
    super.key,
    required this.featureId,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return RoundCard(
      child: Row(
        children: [
          FeatureIcon(featureId: featureId, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(color: miniAppMuted, height: 1.3)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// A One UI-style stadium (pill) action button. A null [onTap] renders it
/// disabled and muted. Mirrors the clock's `_ClockPillButton`, accent-aware.
class MiniPillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final Color textColor;
  final VoidCallback? onTap;
  final double height;

  const MiniPillButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
    this.textColor = Colors.white,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? color : miniAppSurface,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 19, color: enabled ? textColor : miniAppMuted),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  color: enabled ? textColor : miniAppMuted,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One action inside a [MiniActionFab].
class MiniFabAction {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const MiniFabAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
}

/// Bottom-right floating pill holding one or two icon actions, like the
/// reference vault FAB ("add file" + "new album").
class MiniActionFab extends StatelessWidget {
  final Color color;
  final List<MiniFabAction> actions;

  const MiniActionFab({
    super.key,
    required this.color,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      shadowColor: Colors.black54,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) Container(width: 1, height: 30, color: Colors.white24),
            Tooltip(
              message: actions[i].tooltip,
              child: InkWell(
                onTap: actions[i].onTap,
                child: SizedBox(
                  width: 64,
                  height: 56,
                  child: Icon(actions[i].icon, color: Colors.white),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A tappable row with a tinted rounded-square icon tile, title, optional
/// subtitle, and a trailing widget (defaults to a chevron). Used for the
/// "Upgrade protection" lists and permission checklists.
class MiniFeatureRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const MiniFeatureRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RoundCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style:
                          const TextStyle(color: miniAppMuted, height: 1.25)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing ?? const Icon(Icons.chevron_right, color: miniAppMuted),
        ],
      ),
    );
  }
}

/// A "Protect more apps" upsell row: leading app icon, name, reason, and an
/// accent pill button that flips between an outlined call-to-action and a
/// filled "done" state.
class MiniAppUpsellRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final String actionLabel;
  final String activeLabel;
  final bool active;
  final Color accent;
  final ValueChanged<bool> onChanged;

  const MiniAppUpsellRow({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.activeLabel,
    required this.active,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RoundCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: miniAppMuted, height: 1.25)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _Pill(
            label: active ? activeLabel : actionLabel,
            active: active,
            accent: accent,
            onTap: () => onChanged(!active),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? accent : Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: accent, width: 1.4)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 38,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// A muted, all-caps-ish section label for grouping rows ("Protect more apps").
class MiniSectionHeader extends StatelessWidget {
  final String title;

  const MiniSectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Text(
        title,
        style: const TextStyle(
          color: miniAppMuted,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Full-screen confirmation shown after a privacy action (hide a file, lock an
/// app). A bold accent-gradient hero with a checkmark sits over a dark sheet of
/// follow-up [sections] (e.g. "Protect more apps", "Upgrade protection").
class MiniSuccessScreen extends StatelessWidget {
  final Color accent;
  final String headline;
  final String detail;
  final List<Widget> sections;

  const MiniSuccessScreen({
    super.key,
    required this.accent,
    required this.headline,
    required this.detail,
    this.sections = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: miniAppThemeOf(context, accent),
      child: Scaffold(
        backgroundColor: miniAppBackground,
        body: SafeArea(
          top: false,
          child: ScrollConfiguration(
            behavior: const MiniAppScrollBehavior(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Hero(accent: accent, headline: headline, detail: detail),
                Expanded(
                  child: sections.isEmpty
                      ? const SizedBox.shrink()
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
                          children: sections,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final Color accent;
  final String headline;
  final String detail;

  const _Hero({
    required this.accent,
    required this.headline,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(24, top + 16, 24, 36),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, Color.lerp(accent, Colors.black, 0.45)!],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
          const SizedBox(height: 26),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  headline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.check_circle,
                  color: Colors.white.withValues(alpha: 0.55), size: 64),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            detail,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A dark rounded text-input dialog (clear-X suffix, Cancel / accent OK), used
/// for "New album" and rename. Returns the trimmed text, or null if cancelled
/// or left empty.
Future<String?> showMiniTextDialog(
  BuildContext context, {
  required String title,
  required Color accent,
  String initialValue = '',
  String hintText = '',
  String confirmLabel = 'OK',
}) {
  final controller = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (context) {
      return Theme(
        data: miniAppThemeOf(context, accent),
        child: StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: miniAppSurface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22)),
              title: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: false,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (value) => Navigator.of(context)
                        .pop(value.trim().isEmpty ? null : value.trim()),
                    decoration: InputDecoration(
                      hintText: hintText,
                      filled: true,
                      fillColor: miniAppSurface2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: controller.text.isEmpty
                          ? null
                          : IconButton(
                              icon:
                                  const Icon(Icons.close, color: miniAppMuted),
                              onPressed: () => setState(controller.clear),
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: MiniPillButton(
                          label: 'Cancel',
                          color: miniAppSurface2,
                          height: 48,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MiniPillButton(
                          label: confirmLabel,
                          color: accent,
                          height: 48,
                          onTap: () {
                            final text = controller.text.trim();
                            Navigator.of(context)
                                .pop(text.isEmpty ? null : text);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}
