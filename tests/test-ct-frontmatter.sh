#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_eq() {
  if [[ "$1" == "$2" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: expected '$2', got '$1'"
    FAIL=$((FAIL + 1))
  fi
}

assert_true() {
  if "$@"; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: command failed: $*"
    FAIL=$((FAIL + 1))
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

FILE="$TMPDIR/entry.md"
cat > "$FILE" <<'EOF'
---
title: Sample Entry
importance: 64
accessCount: 3
---

Hello world.
EOF

assert_true bash scripts/ct-frontmatter.sh has "$FILE"
assert_eq "$(bash scripts/ct-frontmatter.sh get "$FILE" title)" "Sample Entry"
assert_eq "$(bash scripts/ct-frontmatter.sh get "$FILE" importance)" "64"

bash scripts/ct-frontmatter.sh set "$FILE" importance 72
assert_eq "$(bash scripts/ct-frontmatter.sh get "$FILE" importance)" "72"

bash scripts/ct-frontmatter.sh inc "$FILE" accessCount
assert_eq "$(bash scripts/ct-frontmatter.sh get "$FILE" accessCount)" "4"

echo ""
echo "Frontmatter test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
