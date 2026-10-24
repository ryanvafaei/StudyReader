#!/bin/bash
# Run tests. Usage: ./scripts/test.sh [Target/Suite[/test] ...]
#   no arguments  -> full test suite
#   arguments     -> passed as -only-testing: filters, e.g. ./scripts/test.sh StudyReaderTests/FileStoreTests
# Runs outside the Claude Code sandbox (see .claude/settings.json). Agents must not edit this file.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcodegen generate --use-cache --quiet
filters=()
for t in "$@"; do filters+=("-only-testing:$t"); done
set +e
xcodebuild -project StudyReader.xcodeproj -scheme StudyReader -destination 'platform=macOS' -allowProvisioningUpdates \
  -derivedDataPath build/DerivedData test ${filters[@]+"${filters[@]}"} > build/test.log 2>&1
status=$?
set -e
grep -E "error:|failed|passed|BUILD (SUCCEEDED|FAILED)|TEST (SUCCEEDED|FAILED)|Test run with" build/test.log || true
echo "Full log: build/test.log"
exit $status
