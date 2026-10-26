#!/bin/bash
# Run the XCUITest suite (scheme StudyReaderUITests).
# Usage: ./scripts/uitest.sh                                   -> all UI tests
#        ./scripts/uitest.sh StudyReaderUITests/<Class>[/<test>] ...   -> only these
# The tests launch the Debug app with an in-memory library (-StudyReaderInMemory, ADR-0011) and take over the
# screen while they run. Screenshots the tests attach are exported to build/ui-screenshots/ (manifest.json lists
# which test each file belongs to).
# Runs outside the Claude Code sandbox (see .claude/settings.json). Agents must not edit this file.
set -euo pipefail
# No Xcode on Linux (e.g. a Claude Code cloud session): run this step on GitHub Actions instead (ADR-0020).
if [ "$(uname -s)" != "Darwin" ]; then exec "$(dirname "$0")/ci.sh" uitest "$@"; fi
cd "$(dirname "$0")/.."
mkdir -p build
xcodegen generate --use-cache --quiet
filters=()
for t in "$@"; do filters+=("-only-testing:$t"); done
rm -rf build/UITestResults.xcresult build/ui-screenshots
set +e
xcodebuild -project StudyReader.xcodeproj -scheme StudyReaderUITests -destination 'platform=macOS' -allowProvisioningUpdates \
  -derivedDataPath build/DerivedData -resultBundlePath build/UITestResults.xcresult \
  test ${filters[@]+"${filters[@]}"} > build/uitest.log 2>&1
status=$?
set -e
mkdir -p build/ui-screenshots
if [ -d build/UITestResults.xcresult ]; then
  xcrun xcresulttool export attachments --path build/UITestResults.xcresult --output-path build/ui-screenshots > /dev/null 2>&1 \
    || echo "Note: couldn't export screenshots; open build/UITestResults.xcresult in Xcode instead."
fi
grep -E "error:|Test Case .*(passed|failed)|XCTAssert|BUILD (SUCCEEDED|FAILED)|TEST (SUCCEEDED|FAILED)|Executed [0-9]+ test" build/uitest.log || true
echo "Full log: build/uitest.log | Screenshots: build/ui-screenshots/ | Result bundle: build/UITestResults.xcresult"
exit $status
