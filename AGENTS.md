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
