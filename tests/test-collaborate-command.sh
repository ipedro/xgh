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

assert_file_exists "commands/collaborate.md"
assert_contains "commands/collaborate.md" "/xgh collaborate"
assert_contains "commands/collaborate.md" "workflow"
assert_contains "commands/collaborate.md" "dispatcher"

echo ""
echo "Collaborate command test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
