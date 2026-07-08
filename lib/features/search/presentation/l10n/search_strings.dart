/// Feature-specific, user-facing strings for the Search feature.
///
/// Template for the per-feature localization pattern from
/// ARCHITECTURE_ANALYSIS.md. Move hardcoded `Text(...)`/hint strings out of the
/// search screens into here, grouped by purpose. Replicate this file under each
/// feature's `presentation/l10n/` as strings are extracted.
class SearchStrings {
  SearchStrings._();

  // ========== Input fields ==========
  static const String searchHint = 'Search apps, contacts, and more';

  // ========== Empty states ==========
  static const String noResults = 'No results';
}
