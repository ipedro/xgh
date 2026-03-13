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

assert_file_exists "commands/query.md"
assert_file_exists "commands/curate.md"
assert_file_exists "commands/status.md"

assert_contains "commands/query.md" "/xgh query"
assert_contains "commands/query.md" "context-tree.sh search"

assert_contains "commands/curate.md" "/xgh curate"
assert_contains "commands/curate.md" "ct-sync.sh curate"

assert_contains "commands/status.md" "/xgh status"
assert_contains "commands/status.md" "_manifest.json"

echo ""
echo "Commands test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
