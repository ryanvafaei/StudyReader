# ADR-0020: Cloud sessions and GitHub Actions

- Status: Accepted
- Date: 2026-10-26

## Context
The user wants the work to continue while the Mac is off or in use: Claude Code runs as a cloud session, and builds and tests run on GitHub Actions instead of the user's MacBook. Cloud sessions run Ubuntu 24.04 (x86_64), so they can't run Xcode, the app, XCUITest or Peekaboo. GitHub's `xcode-27` runners run macOS 27 + Xcode 27 on Apple Silicon. The repository is private on GitHub (`StudyReader`, default branch `master`).

## Decision
- **One workflow**, `.github/workflows/ci.yml`, on the `xcode-27` runner:
  - push to `master`: build + unit tests;
  - push to `ci-scratch`: the suite named in the commit's `.ci-request` file;
  - manual run: any suite (`unit`, `build`, `ui`, `all`, `fresh-clone`).
  It skips docs-only pushes (`docs/**`, `**/*.md`, `.claude/**`), cancels superseded `ci-scratch` runs, posts a summary as a commit comment, and uploads logs and UI screenshots as the `ci-results` artifact (7 days).
- **`./scripts/ci.sh`** runs a step from any machine without Xcode. It snapshots the working tree (tracked and untracked files, minus `.gitignore`) as a commit on top of HEAD with a `.ci-request` file, force-pushes it to `ci-scratch`, waits for the run, prints the summary and downloads the artifact to `build/ci/<run id>/`. HEAD, the index and the working tree aren't touched. It uses only the GitHub REST API, because the cloud GitHub proxy blocks GraphQL.
- **Same commands everywhere.** On Linux, `build.sh`, `test.sh`, `uitest.sh` and `check-fresh-clone.sh` forward to `ci.sh`, so agent instructions don't change. `run-app.sh` and `lsregister-clean.sh` need a Mac and exit with code 3 elsewhere.
- **CI signing is ad hoc.** Runners aren't registered devices, so `scripts/ci/prepare-signing.sh` drops the `keychain-access-groups` entitlement in the CI checkout only, and `scripts/ci/run.sh` signs with `CODE_SIGN_IDENTITY=-`. Team signing and the keychain entitlement stay unchanged for local builds (ADR-0011). Anything that needs the keychain entitlement (Google sign-in surviving a restart, T72) is checked on the Mac.
- **Push after every commit.** An approved task is committed and pushed to `master` right away. CI on `master` must be green before the next task starts. Force-pushing `master` and rewriting history stay forbidden; only `ci.sh` force-pushes, and only `ci-scratch`.
- **Mac-only checks become NEEDS HUMAN.** ui-tester's Peekaboo pass, Finder drag-and-drop, light/dark appearance and keychain checks can't run in the cloud or on runners. In a cloud session ui-tester runs the XCUITests through CI, reviews the downloaded screenshots, and lists the rest under "Needs a Mac" in VISUAL_CHECKS.md. The session keeps working; the user checks those items on the Mac when convenient.
- **Reference repos** (`.references/`, git-ignored) are fetched in cloud sessions by the SessionStart hook `scripts/session-start.sh`. If the cloud proxy blocks the clone, tasks that need them say so.
- **Long commands.** `.claude/settings.json` sets `BASH_DEFAULT_TIMEOUT_MS` to 40 minutes and `BASH_MAX_TIMEOUT_MS` to 70 minutes, so a CI wait isn't cut off.

## Alternatives considered
A local macOS VM (Tart): no ready macOS 27 image, and the Mac has about 10 GB free. A self-hosted runner on the user's Mac: the laptop would still do the work. Running the UI suite on every push: too many macOS minutes for a private repo.

## Consequences
- A test run now takes minutes of waiting on CI instead of running locally, and uses GitHub Actions minutes (private repo: included monthly minutes, then billed per minute). Docs-only commits and `.claude/` changes don't trigger CI.
- The cloud environment must allow GitHub's artifact storage (`*.blob.core.windows.net`) for logs and screenshots; without it only the summary comment is available.
- The `ci-scratch` branch is rewritten on every `ci.sh` call. Never base work on it.
- The local workflow on the Mac is unchanged and still works (local scripts, Peekaboo, ui-tester's full pass).
