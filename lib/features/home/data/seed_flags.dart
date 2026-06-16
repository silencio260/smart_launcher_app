// SharedPreferences keys for one-shot, first-run launcher state.
//
// Centralized so the Dev View "Simulate fresh install" maintenance action can
// clear exactly the same keys the home screen and workspace write — keeping a
// single source of truth instead of duplicated string literals that could
// drift apart.

/// Set once the default home layout has been seeded on a fresh install.
const kDefaultLayoutSeededFlag = 'default_layout_seeded_v1';

/// Set once the built-in launcher-feature icons have been seeded.
const kFeatureIconsSeededFlag = 'launcher_feature_icons_seeded_v1';

/// Persisted serialized workspace layout (WorkspaceCubit).
const kWorkspaceLayoutKey = 'workspace_layout_v1';
