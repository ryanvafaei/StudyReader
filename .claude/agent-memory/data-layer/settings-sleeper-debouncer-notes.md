---
name: settings-sleeper-debouncer-notes
description: T33 core support files (Hashing, Sleeper, Debouncer, SettingsStore) and their test helpers; UserDefaults Sendable pitfall
metadata:
  type: reference
---

- Files: `Core/Support/Hashing.swift`, `Sleeper.swift`, `Debounce.swift`, `SettingsStore.swift` (also holds `LibraryLayout`/`LibrarySort`). Test helpers: `StudyReaderTests/Support/TestSleepers.swift` (`ImmediateSleeper`, `ManualSleeper`), `TestSettings.swift` (`make()`, `remove(_:)`).
- `UserDefaults` is NOT Sendable under Swift 6 strict concurrency. A `let defaults: UserDefaults` stored property in a Sendable struct fails the build. `SettingsStore` stores `suiteName: String?` and resolves `defaults` per access (`UserDefaults(suiteName:) ?? .standard`). ADR-0015 allows this fallback.
- `SettingsStore(suiteName: nil)` is `.standard()`; `init(defaults:)` no longer exists.
- `Debouncer` uses a generation counter bumped by schedule, flush and cancel. A sleeping task runs its action only if the counter is unchanged.
- `ManualSleeper.waitForSleepers(n)` yields up to 10_000 times, then `Issue.record`.
- `#expect(throws: (any Error).self) { ... }` works for "any error" checks.
