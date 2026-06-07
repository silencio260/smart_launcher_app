import 'package:flutter/foundation.dart';

/// The three kinds of "page" the home pager can show. [home] pages are the
/// editable workspace pages stored in `WorkspaceCubit.state.pages`. [discover]
/// and [library] are the flanking, non-editable special pages (a Discover feed
/// to the far left and an App Library to the far right). The special pages are
/// NOT part of the workspace page list, so they never appear in the edit-mode
/// page manager / dots / reorder list.
enum HomeSection { discover, home, library }

/// Pure value object describing how the flat pager indices map to home pages
/// and special pages. Rebuilt cheaply on every [WorkspaceView] build from the
/// current settings + home page count — it holds no widget state.
///
/// Pager index layout (with both specials enabled):
/// ```
///   0            1 .. homeCount      homeCount+1
/// [discover] [ home 0 .. home N ] [ library ]
/// ```
/// All index conversions in the workspace funnel through this object so the
/// `+ leadingCount` offset is only ever applied in one place per direction.
@immutable
class PagerLayout {
  const PagerLayout({
    required this.leadingCount,
    required this.trailingCount,
    required this.homeCount,
  });

  /// 1 when the Discover page is enabled (it occupies pager index 0), else 0.
  final int leadingCount;

  /// 1 when the App Library page is enabled (it occupies the last index), else 0.
  final int trailingCount;

  /// Number of real, editable home pages (`WorkspaceCubit.state.pages.length`).
  final int homeCount;

  /// Total number of pager entries.
  int get itemCount => leadingCount + homeCount + trailingCount;

  /// True when at least one flanking special page exists. Infinite scrolling is
  /// force-disabled in this case (a wrap-around pager has no fixed edges).
  bool get hasSpecials => leadingCount + trailingCount > 0;

  /// The controller (pager) index for a 0-based home page index.
  int homeToController(int homeIndex) => leadingCount + homeIndex;

  /// The first/last home page positions in controller space.
  int get firstHomeController => leadingCount;
  int get lastHomeController => leadingCount + (homeCount - 1);

  /// The controller index of the trailing App Library page (only meaningful
  /// when [trailingCount] == 1).
  int get libraryController => leadingCount + homeCount;

  /// Which section a pager index belongs to.
  HomeSection sectionFor(int controllerIndex) {
    if (leadingCount > 0 && controllerIndex < leadingCount) {
      return HomeSection.discover;
    }
    if (trailingCount > 0 && controllerIndex >= leadingCount + homeCount) {
      return HomeSection.library;
    }
    return HomeSection.home;
  }

  /// The nearest real home page index for any pager index. A pager index that
  /// lands on a special page clamps to the closest real home page so drag-drop
  /// resolution never targets a special page.
  int homeIndexFor(int controllerIndex) {
    if (homeCount <= 0) return 0;
    return (controllerIndex - leadingCount).clamp(0, homeCount - 1);
  }

  /// Opacity for the dock + Smart-search pill "chrome" given a fractional
  /// controller scroll position. 1.0 across the whole home band; ramps linearly
  /// to 0.0 over the half-page adjacent to a special page so the dock fades out
  /// as the special page slides in.
  double chromeOpacityFor(double controllerPage) {
    if (!hasSpecials) return 1.0;
    final firstHome = firstHomeController.toDouble();
    final lastHome = lastHomeController.toDouble();
    if (controllerPage <= firstHome - 1) return 0.0;
    if (controllerPage >= lastHome + 1) return 0.0;
    if (controllerPage < firstHome) {
      // Between Discover (firstHome-1) and the first home page.
      return (controllerPage - (firstHome - 1)).clamp(0.0, 1.0);
    }
    if (controllerPage > lastHome) {
      // Between the last home page and the Library (lastHome+1).
      return (lastHome + 1 - controllerPage).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  /// Horizontal slide fraction (-1..1) for the dock + Smart-search pill chrome.
  /// The chrome is a fixed bottom overlay, so without this it would dissolve in
  /// place while the special page slides in underneath — a jarring "floating"
  /// look. Translating it by `fraction * pageWidth` makes it travel off-screen
  /// WITH the home content: +1 means slid a full page right (toward Discover),
  /// -1 a full page left (toward Library). 0 across the whole home band.
  double chromeSlideFor(double controllerPage) {
    if (!hasSpecials) return 0.0;
    final firstHome = firstHomeController.toDouble();
    final lastHome = lastHomeController.toDouble();
    if (controllerPage < firstHome) {
      return (firstHome - controllerPage).clamp(0.0, 1.0);
    }
    if (controllerPage > lastHome) {
      return (lastHome - controllerPage).clamp(-1.0, 0.0);
    }
    return 0.0;
  }

  @override
  bool operator ==(Object other) =>
      other is PagerLayout &&
      other.leadingCount == leadingCount &&
      other.trailingCount == trailingCount &&
      other.homeCount == homeCount;

  @override
  int get hashCode => Object.hash(leadingCount, trailingCount, homeCount);
}
