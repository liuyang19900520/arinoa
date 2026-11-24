# AGENTS.md — rules for AI agents working on Arinoa

Arinoa is an iOS beauty camera app (Swift, iOS 17+). The current target and bundle id still use the old name: `BeautyCam`, `com.arinoa.beautycam`, team `3T7MJA53W9`.
Build and device commands are in [CLAUDE.md](CLAUDE.md). These rules apply to every agent: Claude sessions on the Mac,
Claude cloud sessions, and any bot that dispatches work to them. The branch and release flow is the same as Kage Loop (shadow-player).

## Who works where

| Channel | Runs on | Can do |
|---|---|---|
| Yang on the Mac (`~/Code/arinoa`) | Mac | everything: generate the project, build, install on the iPhone |
| Yang on the Claude phone app, cloud session | Linux cloud container | edit code, push a branch, open a PR |
| Grok bot → `claude --remote "…"` | Linux cloud container | same as above; the session shows up in Yang's Claude app |
| Yang on the phone → Remote Control on the Mac's `arinoa` folder | Mac | everything, while the Mac is on |

Cloud containers have **no Xcode**: no `xcodegen`-then-`xcodebuild`, no device install, no XCUITest.
Building and device testing happen on the Mac (or in the CI build on GitHub Actions).

## Rules
- **GitHub is the single source of truth.** Work that isn't pushed doesn't exist. Push your branch before you stop.
- **Branches:** `develop` is the integration branch (it is meant to be the default branch). Work on `feature/…`, `fix/…`, `ci/…`, `docs/…`,
  `claude/…` or `codex/…` and open a PR into `develop`. Never commit straight to `develop`, `main` or `master`.
- **Keep each PR small and on one topic**, and describe what changed and how you checked it.
- **Never merge a PR without Yang's explicit approval.** Don't delete branches, change secrets, or change the default branch.
- **Every push to `develop` uploads a TestFlight build** (`.github/workflows/testflight.yml`; docs-only pushes are skipped).
  Uploading never submits for review. Don't run the TestFlight workflow by hand unless Yang asks.
- **`master` only holds versions already live on the App Store.**
- **App Store review** goes through the `Submit for review` workflow (manual, `confirm=SUBMIT`). Only run it when
  Yang says so after testing the build in TestFlight.
- Release notes for each version live in `submissions/<version>/` (see `submissions/README.md`).
- Secrets live only in GitHub Secrets. Never commit keys, certificates, or personal data
  (`tools/screens/` and device logs contain personal photos and are gitignored).

## Project
- The Xcode project is generated with XcodeGen from `project.yml`. Edit `project.yml`, not the `.xcodeproj`, and run `xcodegen generate`.
- Build check: `xcodebuild -project BeautyCam.xcodeproj -scheme BeautyCam -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- The CI build (`.github/workflows/build.yml`, runs on every push except docs-only) must pass before a PR is ready for review.

See `PLAN.md` for the current to-do list.

## Checks before a PR is ready
- On the Mac: `xcodegen generate`, then the build check above.
- In a cloud session: these can't run. Rely on the CI build result, say in the PR description and in the final message
  what was not verified, and list what Yang should test on the device.
- Camera, beauty effects, and anything visual are confirmed only by Yang's manual test on the phone.

## Release flow (Yang's standard)
- `develop` is where work is integrated and tested. `master` always equals the version live on the App Store.
- Every change goes `feature/*` / `claude/*` / `codex/*` → PR into `develop`. Pushes to `develop` upload a TestFlight build.
- Yang verifies the build in TestFlight, then says "推送 App Store". Only then submit for review.
- After Apple approves and the app is live, merge `develop` into `master` and tag `vX.Y.Z`. No release branches.
- Urgent fix for live users: `hotfix/*` from `master` → PR into `master`, tag, then merge back into `develop`.
- Never merge, submit for review, delete branches, or change secrets/default branch without Yang's explicit approval.

## Grok bot: how to dispatch work

The Grok bot does not edit code itself. It starts Claude cloud sessions from its own computer, logged in to
Yang's Claude account, inside a clone of this repository:

```bash
claude --remote "<task>"
```

- **One task per session.** Split unrelated requests into separate sessions.
- **Write the task so it stands alone.** Include: the goal, the files or screen involved, what "done" looks like,
  and this line: *"Follow AGENTS.md: work on a new branch, push it, open a PR into develop, don't merge."*
- **Don't ask a session to** merge, tag, push to `develop`/`master`, run `Submit for review` or TestFlight, or touch secrets.
  These need Yang's explicit go-ahead, given by Yang directly, not relayed from another message.
- **Report back to Yang** with the PR link, a one-line summary, and what needs a device test.
- If a task needs the real camera or a device, tell Yang it must be checked on the Mac
  (`git fetch origin && git switch <branch>`, `xcodegen generate`, then build and install), or via Remote Control.

## Release signing (CI)

TestFlight uploads sign with one fixed Apple Distribution certificate and one
App Store provisioning profile for `com.arinoa.beautycam`, stored as repository
secrets. CI never creates certificates or profiles; letting it do so (automatic
signing with `-allowProvisioningUpdates` on fresh runners) minted a new
certificate per run and hit Apple's certificate cap.

| Secret | Content |
| --- | --- |
| `DIST_CERT_P12_BASE64` | base64 of the Apple Distribution certificate + private key exported as .p12 |
| `DIST_CERT_PASSWORD` | password of that .p12 |
| `PROVISIONING_PROFILE_BASE64` | base64 of the App Store profile (.mobileprovision) |

The profile expires after a year; renew it in the developer portal and update
`PROVISIONING_PROFILE_BASE64`. `allow_auto_signing` on the TestFlight workflow is
an emergency fallback only.
