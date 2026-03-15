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

assert_file_exists "skills/continuous-learning/continuous-learning.md"
assert_file_exists "skills/curate/curate.md"
assert_file_exists "skills/ask/ask.md"
assert_file_exists "skills/context-tree-maintenance/context-tree-maintenance.md"
assert_file_exists "skills/memory-verification/memory-verification.md"

assert_contains "skills/continuous-learning/continuous-learning.md" "iron law"
assert_contains "skills/continuous-learning/continuous-learning.md" "cipher_memory_search"
assert_contains "skills/curate/curate.md" "frontmatter"
assert_contains "skills/ask/ask.md" "semantic"
assert_contains "skills/context-tree-maintenance/context-tree-maintenance.md" "archive"
assert_contains "skills/memory-verification/memory-verification.md" "top 5"

echo ""
echo "Skills test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
