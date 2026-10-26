#!/bin/bash
# CI only: build and test on the GitHub runner, ad hoc signed (ADR-0020). Writes build/ci-summary.md.
# Usage: scripts/ci/run.sh <build|unit|ui|all|fresh-clone> [Target/Suite[/test] ...]
set -uo pipefail
cd "$(dirname "$0")/../.."
suite="$1"
shift
mkdir -p build
summary=build/ci-summary.md
xcodegen generate --quiet || { echo "xcodegen failed" > "$summary"; exit 1; }

signing=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
common=(-project StudyReader.xcodeproj -destination 'platform=macOS' -derivedDataPath build/DerivedData)
filters=()
for t in "$@"; do filters+=("-only-testing:$t"); done

{
  echo "## CI: $suite"
  echo
  echo "Commit \`${GITHUB_SHA:-local}\` · ${GITHUB_SERVER_URL:-}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"
  if [ $# -gt 0 ]; then echo "Filters: $*"; fi
  echo
} > "$summary"

overall=0

section() { # title, log, exit status, grep pattern
  local title="$1" log="$2" status="$3" pattern="$4"
  {
    if [ "$status" -eq 0 ]; then echo "### $title: PASS"; else echo "### $title: FAIL (exit $status)"; fi
    echo '```'
    grep -E "$pattern" "$log" | head -300 || true
    echo '```'
    echo
  } >> "$summary"
  if [ "$status" -ne 0 ]; then overall=1; fi
}

run_build() {
  xcodebuild "${common[@]}" -scheme StudyReader "${signing[@]}" build > build/build.log 2>&1
  section "Build" build/build.log $? "error:|warning: .*(Sendable|isolat)|BUILD (SUCCEEDED|FAILED)"
}

run_unit() {
  rm -rf build/UnitTestResults.xcresult
  xcodebuild "${common[@]}" -scheme StudyReader "${signing[@]}" -resultBundlePath build/UnitTestResults.xcresult \
    test ${filters[@]+"${filters[@]}"} > build/test.log 2>&1
  section "Unit tests" build/test.log $? "error:|failed|passed|BUILD (SUCCEEDED|FAILED)|TEST (SUCCEEDED|FAILED)|Test run with"
}

run_ui() {
  rm -rf build/UITestResults.xcresult build/ui-screenshots
  xcodebuild "${common[@]}" -scheme StudyReaderUITests "${signing[@]}" -resultBundlePath build/UITestResults.xcresult \
    test ${filters[@]+"${filters[@]}"} > build/uitest.log 2>&1
  local status=$?
  mkdir -p build/ui-screenshots
  xcrun xcresulttool export attachments --path build/UITestResults.xcresult --output-path build/ui-screenshots \
    > /dev/null 2>&1 || true
  section "UI tests" build/uitest.log "$status" \
    "error:|Test Case .*(passed|failed)|BUILD (SUCCEEDED|FAILED)|TEST (SUCCEEDED|FAILED)|Executed [0-9]+ test"
}

case "$suite" in
  build|fresh-clone) run_build ;;
  unit) run_unit ;;
  ui) run_ui ;;
  all) run_unit; run_ui ;;
  *) echo "Unknown suite: $suite" >> "$summary"; overall=1 ;;
esac

if [ "$overall" -eq 0 ]; then echo "**Result: PASS**" >> "$summary"; else echo "**Result: FAIL**" >> "$summary"; fi
cat "$summary"
exit "$overall"
