---
name: xcodegen-and-fsrs-pitfalls
description: Build/test pitfalls hit while setting up project.yml, the test host, and SPM package imports (T01)
metadata:
  type: project
---

- `project.yml` test target has a folder source `StudyReaderTests/Fixtures` with `optional: true`. XcodeGen still fails the build ("couldn't be opened") if the directory is missing. Empty dirs aren't tracked by git, so a fresh clone needs a real fixture file there (T10) or the build breaks.
- swift-fsrs 5.0.0: `FSRSDefaults` is a public class, but its `defaultW` is internal and `defaultWv6` doesn't exist. Use `Rating` (public, CaseIterable) for package-link checks.
- `.gitignore` negation block for `Package.resolved` works: `git check-ignore` confirms it, and `git status -uall StudyReader.xcodeproj` lists only that file.
- `Info.plist` version keys are fixed (T11): `info.properties` sets `CFBundleShortVersionString` to `$(MARKETING_VERSION)` and `CFBundleVersion` to `$(CURRENT_PROJECT_VERSION)`.
- XcodeGen collects folder sources at generate time. After adding a new test file, run `xcodegen generate` again or the build won't see it.
