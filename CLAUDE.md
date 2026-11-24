# CLAUDE.md

Follow [AGENTS.md](AGENTS.md): it holds the rules and build commands for this repo. The to-do list is in [PLAN.md](PLAN.md).

## Workflow on the Mac

Claude develops on this Mac; Yang tests by hand on a USB-connected iPhone.

1. Work on a branch and open a PR into `develop` (never commit straight to `develop`, `main` or `master`).
   Branch, release and agent rules are in `AGENTS.md`.
2. `xcodegen generate`, then the build check from AGENTS.md. Edit `project.yml`, never the generated `.xcodeproj`.
3. Install on the phone (free personal team; signing expires after 7 days, then reinstall):
   - `xcodebuild -project BeautyCam.xcodeproj -scheme BeautyCam -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates build`
   - `xcrun devicectl list devices`, then `xcrun devicectl device install app --device <id> build/Build/Products/Release-iphoneos/BeautyCam.app`
4. Keep verification light: build, install, at most a quick log check. Tell Yang what to try on the phone.
   `tools/ui-test.sh` (XCUITest tour + screenshots) only when Yang asks.

## Cloud sessions (Claude Code on the web / phone / `claude --remote`)

Cloud sessions run in a Linux container with no Xcode, so they cannot run `xcodegen`/`xcodebuild`,
install on a device, or run `tools/ui-test.sh` / `tools/filter-preview/run.sh`.

- Don't try to build or install. Edit code (and `project.yml`, never the generated `.xcodeproj`),
  keep changes small and reviewable, push a branch and open a PR into `develop`. Don't merge it.
- The CI build on GitHub Actions is the only compile check. Check its result on the PR before calling the work done.
- In the final message, list what was not verified and tell Yang how to test it on the Mac:
  `git fetch origin && git switch <branch>`, `xcodegen generate`, then build and install as above.
- To verify on a real device without the Mac at hand, Yang can use a Remote Control session on the Mac's
  `arinoa` folder instead of a cloud session.
