# T74a: Open With / Finder file opening regression from T72

- **Phase:** 1 (T74 checkpoint, `docs/checkpoints/T74-cloud-2026-10-28.md`; spec FAIL: F-02 import by Open With / double-click / Dock drop)
- **Agent:** ui-builder
- **Depends on:** T72
- **Visual check needed:** yes (Mac: Finder Open With, Dock drop, and Google's sign-in redirect together)

## Goal
All three `StudyReaderUITests/ExternalOpenTests` fail since T72 (they passed at T69): `testDuplicateOpenWithStillShowsTheSummaryAlert`, `testOpenWithWhenNotRunningLaunchesOnceAndImports`, `testOpenWithWhileRunningImportsIntoTheRunningInstance`. The hierarchy dumps show a normal library with no card for the opened file. Suspected cause (unverified): T72 added `.onOpenURL` at `StudyReaderApp.swift` (~lines 16-21) which ignores file URLs and is the only `.onOpenURL` in the app, so SwiftUI no longer calls `AppDelegate.application(_:open:)` and file URLs never reach `ExternalURLRouter`. T72 also routes non-file URLs to `GoogleSignInAuth.handle` in `AppDelegate.application(_:open:)`.

## What to do
1. Reproduce from the CI evidence (`build/ci/40625477081/`, uitest.log and hierarchy dumps for the three tests) and confirm the cause by reading `StudyReaderApp`, `AppDelegate`, `ExternalURLRouter`.
2. Fix at the root so file URLs (Open With, double-click, Dock drop, cold start and running) reach `ExternalURLRouter` again AND Google's sign-in redirect URL still reaches `GoogleSignInAuth.handle` (exactly one place handles each kind; no double handling). Options: route file URLs to `ExternalURLRouter.shared.receive` inside `.onOpenURL`, or remove `.onOpenURL` and let the delegate handle both. Pick the simplest that keeps both flows and say why.
3. Add a unit test for the URL routing decision if the routing logic can be extracted into a pure function (file URL → router, non-file URL → Google handler, other schemes ignored).
4. Don't weaken `ExternalOpenTests`.

## Acceptance criteria
1. The three `ExternalOpenTests` pass on CI: run ONLY `./scripts/ci.sh uitest StudyReaderUITests/ExternalOpenTests` (this task may run its own targeted UI tests; max 2 attempts; never two CI jobs at once).
2. `./scripts/build.sh` and unit tests (filtered) green.
3. Mac check listed in VISUAL_CHECKS.md: Finder Open With, Dock drop and Google's sign-in redirect still work.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
