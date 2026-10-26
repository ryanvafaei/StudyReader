#!/bin/bash
# SessionStart hook (.claude/settings.json). Cloud sessions only (CLAUDE_CODE_REMOTE=true): fetch the read-only
# reference repos that DEPENDENCIES.md §3 points to into .references/ (git-ignored). Never fails the session.
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/..}" || exit 0
mkdir -p .references
while read -r name url; do
  [ -d ".references/$name" ] && continue
  if ! timeout 120 git clone --depth 1 --quiet "$url" ".references/$name" 2> /dev/null; then
    rm -rf ".references/$name"
    echo "SessionStart: couldn't fetch reference repo $name ($url); tasks that need it should say so." >&2
  fi
done << 'LIST'
reader-source https://github.com/Marvy101/reader-source
annotate https://github.com/mweingartner/annotate
YoPDF https://github.com/basicv8vc/YoPDF
LIST
exit 0
