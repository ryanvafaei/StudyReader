# ADR-0002: Generate the Xcode project with XcodeGen

- Status: Accepted
- Date: 2026-10-23

## Context
Agents must add files, targets, packages, and entitlements. Editing `project.pbxproj` by hand or by model is error-prone and produces unreadable diffs.

## Decision
`project.yml` is the source of truth; `.xcodeproj` is git-ignored and generated with `xcodegen generate` before every build. Only `project.yml` is edited.

## Alternatives considered
Hand-maintained Xcode project with folder-synchronized groups; Tuist; pure SwiftPM app with a bundling script.

## Consequences
User installs XcodeGen once (`brew install xcodegen`). Build commands always run `xcodegen generate` first.
