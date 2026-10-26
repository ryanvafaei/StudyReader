#!/bin/bash
# Run a build or test step on GitHub Actions (macOS 27 + Xcode 27) and print its result here (ADR-0020).
# Used where there's no Xcode, e.g. a Claude Code cloud session: build.sh, test.sh, uitest.sh and
# check-fresh-clone.sh forward to it automatically on Linux.
#
# Usage: ./scripts/ci.sh build                      build the app
#        ./scripts/ci.sh test [Target/Suite[/test] ...]    unit tests (all, or the filters)
#        ./scripts/ci.sh uitest [StudyReaderUITests/<Class>[/<test>] ...]   UI tests + screenshots
#        ./scripts/ci.sh fresh-clone                build the last commit only (uncommitted changes left out)
#        ./scripts/ci.sh status                     result of the latest CI run on master
#
# How: the working tree (tracked + untracked, minus .gitignore) is committed as a snapshot on top of HEAD, with a
# .ci-request file naming the suite, and force-pushed to the ci-scratch branch. HEAD, the index and the working
# tree are not changed. The workflow posts its summary as a commit comment on the snapshot; this script waits for
# it, prints it, and downloads logs and screenshots to build/ci/<run id>/.
# Takes minutes (build ~10, unit tests ~15, UI tests ~30): run it with a long timeout.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v gh > /dev/null || { echo "gh (GitHub CLI) is required." >&2; exit 2; }
step="${1:-}"
[ -n "$step" ] || { sed -n '5,12p' "$0"; exit 2; }
shift

# owner/repo from the origin URL (works for https, ssh and the cloud session's local git proxy URL).
repo=$(git remote get-url origin | sed -E 's#\.git$##; s#^.*[:/]([^/:]+)/([^/]+)$#\1/\2#')
[ -n "$repo" ] || { echo "No GitHub origin remote." >&2; exit 2; }

case "$step" in
  build) suite=build; timeout=1800 ;;
  test) suite=unit; timeout=2700 ;;
  uitest) suite=ui; timeout=4200 ;;
  fresh-clone) suite=fresh-clone; timeout=1800 ;;
  status) suite=status; timeout=0 ;;
  *) echo "Unknown step: $step" >&2; exit 2 ;;
esac

filters="$*"
if [ -n "$filters" ] && ! printf '%s' "$filters" | grep -Eq '^[A-Za-z0-9_/. ]+$'; then
  echo "Filters may only contain test identifiers: $filters" >&2
  exit 2
fi

run_url() { echo "https://github.com/$repo/actions/runs/$1"; }

wait_for_run() { # sha, timeout seconds -> prints run id
  local sha="$1" limit="$2" run_id="" start=$SECONDS
  while [ -z "$run_id" ]; do
    run_id=$(gh api "repos/$repo/actions/runs?head_sha=$sha&per_page=1" --jq '.workflow_runs[0].id // empty' 2> /dev/null || true)
    [ -n "$run_id" ] && break
    if [ $((SECONDS - start)) -gt 300 ]; then
      echo "No CI run started for $sha within 5 minutes. Check https://github.com/$repo/actions" >&2
      exit 1
    fi
    sleep 10
  done
  echo "CI run: $(run_url "$run_id")" >&2
  local status=""
  while true; do
    status=$(gh api "repos/$repo/actions/runs/$run_id" --jq .status 2> /dev/null || echo unknown)
    [ "$status" = completed ] && break
    if [ $((SECONDS - start)) -gt "$limit" ]; then
      echo "CI run still $status after $((limit / 60)) minutes: $(run_url "$run_id")" >&2
      exit 1
    fi
    sleep 20
  done
  echo "$run_id"
}

report() { # sha, run id
  local sha="$1" run_id="$2" conclusion out
  conclusion=$(gh api "repos/$repo/actions/runs/$run_id" --jq .conclusion)
  out="build/ci/$run_id"
  mkdir -p "$out"
  # Summary: the commit comment the workflow posted (REST API only; works through the cloud GitHub proxy).
  gh api "repos/$repo/commits/$sha/comments" --jq '.[-1].body // empty' > "$out/summary.md" 2> /dev/null || true
  if [ -s "$out/summary.md" ]; then
    cat "$out/summary.md"
  else
    echo "(No summary comment found; see $(run_url "$run_id"))"
  fi
  # Logs and screenshots: the artifact zip. Its download redirects to GitHub's blob storage, which a cloud
  # environment must allow (*.blob.core.windows.net); otherwise only the summary above is available.
  local artifact
  artifact=$(gh api "repos/$repo/actions/runs/$run_id/artifacts" --jq '.artifacts[] | select(.name=="ci-results") | .id' 2> /dev/null | head -1 || true)
  if [ -n "$artifact" ] && gh api "repos/$repo/actions/artifacts/$artifact/zip" > "$out/results.zip" 2> /dev/null \
      && unzip -oq "$out/results.zip" -d "$out" 2> /dev/null; then
    rm -f "$out/results.zip"
    echo "Logs and screenshots: $out/"
  else
    rm -f "$out/results.zip"
    echo "Couldn't download the results artifact (logs, screenshots). Open $(run_url "$run_id")"
  fi
  echo "Conclusion: $conclusion"
  [ "$conclusion" = success ]
}

if [ "$suite" = status ]; then
  sha=$(gh api "repos/$repo/commits/master" --jq .sha)
  run_id=$(gh api "repos/$repo/actions/runs?branch=master&per_page=1" --jq '.workflow_runs[0].id // empty')
  [ -n "$run_id" ] || { echo "No CI runs on master yet."; exit 0; }
  status=$(gh api "repos/$repo/actions/runs/$run_id" --jq .status)
  [ "$status" = completed ] || { echo "Latest master run is $status: $(run_url "$run_id")"; exit 0; }
  run_sha=$(gh api "repos/$repo/actions/runs/$run_id" --jq .head_sha)
  [ "$run_sha" = "$sha" ] || echo "Note: the latest run is for ${run_sha:0:7}, master is at ${sha:0:7}."
  report "$run_sha" "$run_id"
  exit $?
fi

# Snapshot commit with a temporary index, so HEAD, the real index and the working tree stay untouched.
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
export GIT_INDEX_FILE="$tmpdir/index"
git read-tree HEAD
if [ "$suite" != fresh-clone ]; then
  git add -A
fi
request_blob=$(printf 'suite=%s\nfilters=%s\n' "$suite" "$filters" | git hash-object -w --stdin)
git update-index --add --cacheinfo 100644 "$request_blob" .ci-request
tree=$(git write-tree)
unset GIT_INDEX_FILE
snapshot=$(git commit-tree "$tree" -p HEAD -m "CI snapshot: $suite ${filters:+($filters) }of $(git rev-parse --short HEAD)")
git push --force --quiet origin "$snapshot:refs/heads/ci-scratch"
echo "Pushed snapshot ${snapshot:0:7} to ci-scratch ($suite${filters:+: $filters}). Waiting for CI..." >&2

run_id=$(wait_for_run "$snapshot" "$timeout")
report "$snapshot" "$run_id"
