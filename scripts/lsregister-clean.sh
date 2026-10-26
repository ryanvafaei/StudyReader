#!/bin/bash
# Keep exactly one StudyReader.app registered with LaunchServices: this project's build/DerivedData copy.
# Old copies (fresh-clone builds in $TMPDIR, Xcode's own DerivedData, archives) make Finder's "Open With" and the Dock
# launch an old build as a second instance. Only registrations change; no files are deleted.
# Usage: ./scripts/lsregister-clean.sh          -> unregister every other copy, then register ours
#        ./scripts/lsregister-clean.sh --check  -> list registered copies; exit 1 if any copy other than ours is registered
# Runs outside the Claude Code sandbox (see .claude/settings.json). Agents must not edit this file.
set -euo pipefail
if [ "$(uname -s)" != "Darwin" ]; then
  echo "$(basename "$0") needs a Mac. In a cloud session, list this check under Needs a Mac in VISUAL_CHECKS.md (ADR-0020)." >&2
  exit 3
fi
cd "$(dirname "$0")/.."
lsreg=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
ours="$PWD/build/DerivedData/Build/Products/Debug/StudyReader.app"

registered() {
  "$lsreg" -dump | grep -oE '/[^()]*/StudyReader\.app' | sed -E 's/[[:space:]]+$//' | sort -u
}

others=()
while IFS= read -r path; do
  [ -n "$path" ] || continue
  [ "$path" = "$ours" ] || others+=("$path")
done < <(registered)

if [ "${1:-}" = "--check" ]; then
  echo "Registered StudyReader.app copies:"
  registered | sed 's/^/  /'
  if [ ${#others[@]} -gt 0 ]; then
    echo "FAIL: ${#others[@]} copy/copies besides $ours. Run ./scripts/lsregister-clean.sh"
    exit 1
  fi
  echo "OK: only this project's build is registered."
  exit 0
fi

if [ ${#others[@]} -gt 0 ]; then
  for path in "${others[@]}"; do
    "$lsreg" -u "$path" > /dev/null 2>&1 && echo "Unregistered $path" || echo "Couldn't unregister $path"
  done
fi
if [ -d "$ours" ]; then
  "$lsreg" -f "$ours"
  echo "Registered $ours"
else
  echo "No build at $ours yet. Run ./scripts/build.sh, then this script again."
fi
