#!/bin/bash
# Build the app. Usage: ./scripts/build.sh
# Runs outside the Claude Code sandbox (see .claude/settings.json). Agents must not edit this file.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcodegen generate --use-cache --quiet
set +e
xcodebuild -project StudyReader.xcodeproj -scheme StudyReader -destination 'platform=macOS' -allowProvisioningUpdates \
  -derivedDataPath build/DerivedData build > build/build.log 2>&1
status=$?
set -e
grep -E "error:|warning: .*(Sendable|isolat)|BUILD (SUCCEEDED|FAILED)" build/build.log || true
echo "Full log: build/build.log"
exit $status
