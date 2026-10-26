#!/bin/bash
# Verify that a fresh clone of the last commit generates and builds.
# Usage: ./scripts/check-fresh-clone.sh   (only committed files are checked)
# Runs outside the Claude Code sandbox (see .claude/settings.json). Agents must not edit this file.
set -euo pipefail
# No Xcode on Linux (e.g. a Claude Code cloud session): run this step on GitHub Actions instead (ADR-0020).
if [ "$(uname -s)" != "Darwin" ]; then exec "$(dirname "$0")/ci.sh" fresh-clone "$@"; fi
cd "$(dirname "$0")/.."
dest="${TMPDIR:-/tmp}/studyreader-fresh-clone"
rm -rf "$dest"
git clone -q . "$dest"
cd "$dest"
xcodegen generate --quiet
set +e
xcodebuild -project StudyReader.xcodeproj -scheme StudyReader -destination 'platform=macOS' -allowProvisioningUpdates \
  -derivedDataPath "$dest/build" build > "$dest/build.log" 2>&1
status=$?
set -e
grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$dest/build.log" || true
# Unregister the clone's app so Finder's Open With and the Dock never launch this snapshot later
# (a stale copy from an old clone opened as a second instance at the T52 checkpoint).
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -u "$dest/build/Build/Products/Debug/StudyReader.app" > /dev/null 2>&1 || true
echo "Fresh clone at $dest, log: $dest/build.log"
exit $status
