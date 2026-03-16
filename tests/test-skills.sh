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

assert_file_exists "skills/curate/curate.md"
assert_file_exists "skills/ask/ask.md"
assert_file_exists "docs/context-tree-rules.md"

assert_contains "skills/curate/curate.md" "frontmatter"
assert_contains "skills/curate/curate.md" "verification"
assert_contains "skills/ask/ask.md" "semantic"
assert_contains "docs/context-tree-rules.md" "archive"

echo ""
echo "Skills test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
