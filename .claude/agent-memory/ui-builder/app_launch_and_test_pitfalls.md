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
- `Localizable.xcstrings` is empty; SwiftUI literals (`ProgressView("Opening library…")`) are extracted at build via SWIFT_EMIT_LOC_STRINGS.
