---
name: app-launch-and-test-pitfalls
description: SwiftUI launch wiring (AppEnvironment/AppLaunchModel, T08) and test-file pitfalls hit while building it
metadata:
  type: project
---

- `LocalizedError` needs `import Foundation` in test files; `import Testing` alone doesn't bring it in (T08 build failed on this).
- `#Preview { RootView() }` can't compile once `RootView` takes an `AppEnvironment`. Build previews from `AppLaunchModel(makeEnvironment: { try AppEnvironment.inMemory() })` instead of force-trying.
- Counting factory calls: `Mutex<Int>` from `Synchronization` captured in a `@Sendable` closure works without `@unchecked`.
- `AppEnvironment.inMemory()` and `make(fileStore:)` leave temp folders behind; tests remove `fileStore.rootURL.deletingLastPathComponent()` in `defer`.
- Full suite after T08: 69 tests in 17 suites (63 prior + 6 new) pass.
- T15/T27: the in-memory decision is `AppEnvironment.launchTestHostSignals` (three signals, read in `StudyReaderApp.init()`) → `AppLaunchModel.chooseEnvironment`. `usesInMemoryLibrary(environment:arguments:)` was removed in T27. Compute `try FileStore.applicationSupport()` into a local before `#expect`.
- test.sh filters take struct names (`StudyReaderTests/AppEnvironmentTests`), not `@Suite` display names (`AppEnvironment`). A display-name filter runs 0 tests and still prints TEST SUCCEEDED. Check the per-test "passed" lines in build/test.log.
- Swift Testing per-test results appear in the test.log as "Test x() passed"; the xcresult has no test nodes for a display-name filter.
- T23: `start()` is async; factory runs in `Task.detached(priority: .userInitiated) { Result { try factory() } }.value`. Tests `await model.start()` on the @MainActor suite; `AppLaunchModelTests` filter works with `scripts/test.sh`. Failure messages come from `AppLaunchModel.failureMessage(for:)`, never `localizedDescription`.
- `Localizable.xcstrings` is empty; SwiftUI literals (`ProgressView("Opening library…")`) are extracted at build via SWIFT_EMIT_LOC_STRINGS.
