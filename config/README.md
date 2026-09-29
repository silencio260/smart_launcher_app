# App Remote Config

`remote_config.json` is this launcher's Firebase Remote Config template and
bundled defaults. It began as a copy of
`.agents/skills/mobile-app-skills/skills/remote-config/remote_config_template.json`.
Edit this app copy when tuning the launcher. The shared template is a starting
point for other apps, not a live dependency of the shipped app.

The app loads this asset before constructing its Remote Config coordinator.
`LauncherRemoteConfig` checks every value against the shared typed schema plus
`LauncherPolicyKeys`, preserving validation while replacing bundled defaults.
Valid cached and activated Firebase values retain their existing precedence.
Firebase conditions are evaluated by Firebase, not by the local asset loader.

App differences: `min_insta_ad_interval` is 15 seconds (shared default: 10),
`session_replay_percent` remains 100, and `launcher_force_default` defaults to
false. Shared splash/exit keys are retained from the base template; the launcher's
current splash and exit presentation remain app-controlled.

For a future upload or merge, start with this file and compare it with the latest
template exported from the app's Firebase project. Preserve existing conditions,
conditional values, and unrelated remote keys; review any conflicts explicitly.
No Firebase template is published automatically by changing this file.

When adding a key, add its typed schema definition as well as its JSON default.
When adopting shared template changes, merge them into this file and preserve
the launcher's deliberate overrides. Bundled file changes require an app build;
remote changes follow the existing fetch/activation behavior.
