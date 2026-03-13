#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_file_exists() {
  if [[ -f "$1" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: missing file $1"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  if grep -qi "$2" "$1" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 missing '$2'"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists "agents/collaboration-dispatcher.md"
assert_contains "agents/collaboration-dispatcher.md" "dispatch"
assert_contains "agents/collaboration-dispatcher.md" "plan-review"
assert_contains "agents/collaboration-dispatcher.md" "parallel-impl"

echo ""
echo "Collaboration agent test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
