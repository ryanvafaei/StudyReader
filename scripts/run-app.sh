#!/bin/bash
# Start or stop the Debug build for exploratory UI checks (ui-tester agent, Peekaboo).
# It always uses an in-memory library (-StudyReaderInMemory, ADR-0011), so checks never touch the user's library.
# (No -ApplePersistenceIgnoreState: runs that passed it started with no window at all; suspected cause.)
# Usage: ./scripts/run-app.sh        -> quits any running StudyReader, starts build/DerivedData's copy, logs to build/app.log
#        ./scripts/run-app.sh stop   -> quits StudyReader
# Build first with ./scripts/build.sh. Runs outside the Claude Code sandbox. Agents must not edit this file.
set -euo pipefail
if [ "$(uname -s)" != "Darwin" ]; then
  echo "$(basename "$0") needs a Mac. In a cloud session, list this check under Needs a Mac in VISUAL_CHECKS.md (ADR-0020)." >&2
  exit 3
fi
cd "$(dirname "$0")/.."
bundle_id="com.ryanvafaei.StudyReader"
app="$PWD/build/DerivedData/Build/Products/Debug/StudyReader.app"

quit_running() {
  pgrep -x StudyReader > /dev/null || return 0
  osascript -e "tell application id \"$bundle_id\" to quit" > /dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    pgrep -x StudyReader > /dev/null || return 0
    sleep 0.5
  done
  echo "StudyReader didn't quit within 10 seconds. Ask the user to quit it, then run this again." >&2
  exit 1
}

if [ "${1:-}" = "stop" ]; then
  quit_running
  echo "StudyReader stopped."
  exit 0
fi

[ -d "$app" ] || { echo "No build at $app. Run ./scripts/build.sh first." >&2; exit 1; }
quit_running
mkdir -p build
: > build/app.log
# Start the executable directly, not through `open`: `open -a … --stdout …` failed with LaunchServices error -10810
# (2026-10-25). A directly started app still registers as running, so Finder's Open With reaches it.
# OS_ACTIVITY_DT_MODE mirrors os_log (Log.app, Log.files, ...) and AppKit messages to stderr, as Xcode's console does.
OS_ACTIVITY_DT_MODE=YES nohup "$app/Contents/MacOS/StudyReader" -StudyReaderInMemory \
  >> build/app.log 2>&1 < /dev/null &
disown
for _ in $(seq 1 20); do
  pgrep -x StudyReader > /dev/null && break
  sleep 0.5
done
pgrep -x StudyReader > /dev/null || { echo "StudyReader didn't start; see build/app.log" >&2; exit 1; }
# A directly started app isn't activated: its window stays behind the terminal and keystrokes would go to the
# terminal. Bring it to the front (on a running app, `open -a` only activates it).
sleep 1
open -a "$app" || osascript -e "tell application id \"$bundle_id\" to activate" > /dev/null 2>&1 || true
echo "StudyReader is running with an in-memory library. Log: build/app.log"
