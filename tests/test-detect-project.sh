#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }
assert_executable() { if [ -x "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 not executable"; FAIL=$((FAIL+1)); fi; }

assert_file_exists "scripts/detect-project.sh"
assert_executable "scripts/detect-project.sh"
assert_contains "scripts/detect-project.sh" "#!/usr/bin/env bash"
assert_contains "scripts/detect-project.sh" "set -euo pipefail"
assert_contains "scripts/detect-project.sh" "git rev-parse"
assert_contains "scripts/detect-project.sh" "git remote"
assert_contains "scripts/detect-project.sh" "ingest.yaml"
assert_contains "scripts/detect-project.sh" "dependencies"
assert_contains "scripts/detect-project.sh" "XGH_PROJECT"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
