# Smart Launcher — agent entry point

Flutter home-screen replacement built on the GenRevibes starter kit.

- Operating rules: [.agents/AGENTS.md](.agents/AGENTS.md)
- App and kit guidance: [.agents/skills/mobile-app-skills/README.md](.agents/skills/mobile-app-skills/README.md)
- Commit and publication scope: [.agents/skills/commit-policy/SKILL.md](.agents/skills/commit-policy/SKILL.md)

`.agents` and `packages/genrevibes_starter_kit` are submodules. After cloning:

```bash
git submodule update --init
```

## This app's own rules

- Do not build, install or run the app on a device; the developer does that.
  `flutter analyze` on the files you touched is the check to run here.
- Never uninstall, force-stop, clear or disable any app on the developer's
  phone, including this one. It is their daily driver.
- Ships on Google Play: avoid permissions Play rejects, such as an
  AccessibilityService used for anything but accessibility.
