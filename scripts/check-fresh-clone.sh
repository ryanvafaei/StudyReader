#!/bin/bash
# Verify that a fresh clone of the last commit generates and builds.
# Usage: ./scripts/check-fresh-clone.sh   (only committed files are checked)
# Runs outside the Claude Code sandbox (see .claude/settings.json). Agents must not edit this file.
set -euo pipefail
cd "$(dirname "$0")/.."
dest="${TMPDIR:-/tmp}/studyreader-fresh-clone"
rm -rf "$dest"
git clone -q . "$dest"
cd "$dest"
xcodegen generate --quiet
set +e
xcodebuild -project StudyReader.xcodeproj -scheme StudyReader -destination 'platform=macOS' \
  -derivedDataPath "$dest/build" build > "$dest/build.log" 2>&1
status=$?
set -e
grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$dest/build.log" || true
echo "Fresh clone at $dest, log: $dest/build.log"
exit $status
