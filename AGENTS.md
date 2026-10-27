# AGENTS.md — rules for AI agents working on Arinoa

Arinoa is an iOS beauty camera app (Swift, iOS 17+). The current target and bundle id still use the old name: `BeautyCam`, `com.arinoa.beautycam`, team `3T7MJA53W9`.

## Rules
- **GitHub is the single source of truth.** Everything lives in this repo. Local-only changes and notes don't count.
- **Work on a feature branch** (`feature/…`, `fix/…`, `ci/…`, `docs/…`). Never commit straight to `main`.
- **Open a PR into `main`.** Keep each PR small and on one topic, and describe what changed and how you checked it.
- **Never merge a PR without Yang's explicit approval.** Don't delete branches, change secrets, or change the default branch.
- Don't run the TestFlight workflow or upload builds unless Yang asks.

## Project
- The Xcode project is generated with XcodeGen from `project.yml`. Edit `project.yml`, not the `.xcodeproj`, and run `xcodegen generate`.
- Build check: `xcodebuild -project BeautyCam.xcodeproj -scheme BeautyCam -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- The CI build must pass before a PR is ready for review.

See `PLAN.md` for the current to-do list.

## Release flow (Yang's standard)
- `develop` is where work is integrated and tested. `master` always equals the version live on the App Store.
- Every change goes `feature/*` / `claude/*` / `codex/*` → PR into `develop`. Pushes to `develop` upload a TestFlight build.
- Yang verifies the build in TestFlight, then says "推送 App Store". Only then submit for review.
- After Apple approves and the app is live, merge `develop` into `master` and tag `vX.Y.Z`. No release branches.
- Urgent fix for live users: `hotfix/*` from `master` → PR into `master`, tag, then merge back into `develop`.
- Never merge, submit for review, delete branches, or change secrets/default branch without Yang's explicit approval.
