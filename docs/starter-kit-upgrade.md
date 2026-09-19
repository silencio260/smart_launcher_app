# Modular starter-kit migration

The app moves from `edf80cfccbf5b627aa2e3ee11e96edb3592a8a45` to
`c1f264086a00d957cf4959a5df9c1c195a88a789` (remote main verified September 15, 2026).
It consumes the coordinator, analytics/Firebase/Mixpanel/replay, engagement,
storage/SharedPreferences, and ads/AdMob/inline UI packages under `modules/`.
The archived monolith is not a dependency. The replay adapter requires Flutter
3.38 or newer; the app's FVM configuration selects the installed Flutter 3.44.1.

## Saved state

Before initializing retention, wrap SharedPreferences with
`MigratingKeyValueStore` and `EngagementKeys.legacyKeys`:

| Legacy preference | New preference | Type and meaning |
| --- | --- | --- |
| first_install_date | genrevibes.engagement.installed_at.v1 | ISO string; first open |
| last_open_date | genrevibes.engagement.last_opened_at.v1 | ISO string; last open |
| total_app_opens | genrevibes.engagement.total_opens.v1 | int; lifetime opens |
| session_timestamps | genrevibes.engagement.session_timestamps.v1 | string list; ISO session instants |
| daily_open_dates | genrevibes.engagement.daily_open_dates.v1 | string list; ISO active dates |

Existing new keys take precedence. Legacy values remain on disk; later writes
target new keys only, so rolling back sees the history from before migration.
The kit returns current-key read failures, treats failed legacy reads as absent,
and returns the legacy value even if copying it fails. The app preflights these
reads/copies before starting retention, so failures do not overwrite valid history.
The app retains `total_sessions` as an app-owned lifetime counter because the
new tracker only exposes today's sessions. No install ID, onboarding, Hive,
launcher settings, or secure-feature storage keys change.

The new tracker keeps at most 500 session timestamps, preserves active dates,
and reports retention milestones once. The app preserves its existing
`retention_*` event names and includes its lifetime session counter.
Replay remains disabled for debug/development, masks text/images in release,
and pauses inside secure mini-apps. Development ad controls use sample units.

## Verification

- `flutter pub get`: passed; all selected kit packages resolve under `modules/`.
  Existing selected vendor SDK versions were retained. Unused SDK dependencies
  formerly pulled in by the monolith and their generated desktop registrations
  were removed by Flutter.
- `flutter analyze --no-pub lib test`: zero errors; 23 findings in untouched app
  files, plus two new style notices that were subsequently fixed.
- Focused analysis of all eight changed Dart paths: passed with no issues.
- `git diff --check`: passed.
- Native builds, tests, and on-device checks of ads, analytics delivery, replay
  masking, and upgrade storage were not run.

The app uses the kit coordinator for optional module startup and resource scopes
for cleanup. Startup displays loading/retry UI. Hive initialization now reuses
its initialization Future and cipher so retries do not reassign a late-final
field. The parent gitlink change and app migration remain uncommitted.
