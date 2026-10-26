#!/bin/bash
# CI only (ADR-0020): GitHub's runners aren't registered devices, so the team-signed app with the restricted
# keychain-access-groups entitlement can't launch there. Drop that entitlement before XcodeGen runs; run.sh then
# signs everything ad hoc. Refuses to run outside GitHub Actions because it edits project.yml in place.
set -euo pipefail
cd "$(dirname "$0")/../.."
[ "${GITHUB_ACTIONS:-}" = "true" ] || { echo "prepare-signing.sh runs only on GitHub Actions." >&2; exit 1; }
python3 - <<'PY'
import re
path = "project.yml"
text = open(path).read()
new = re.sub(r"\n[ \t]*keychain-access-groups:\n[ \t]*- [^\n]*", "", text)
if new == text:
    raise SystemExit("keychain-access-groups not found in project.yml; update scripts/ci/prepare-signing.sh")
open(path, "w").write(new)
PY
echo "Removed keychain-access-groups for the CI build."
