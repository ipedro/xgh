#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_true() {
  if "$@"; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: command failed: $*"
    FAIL=$((FAIL + 1))
  fi
}

assert_eq() {
  if [[ "$1" == "$2" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: expected '$2', got '$1'"
    FAIL=$((FAIL + 1))
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export XGH_CONTEXT_TREE="$TMPDIR/context-tree"

bash scripts/context-tree.sh init
bash scripts/context-tree.sh create "quality/scoring/example.md" "Scoring Example" "Initial content"

FILE="$XGH_CONTEXT_TREE/quality/scoring/example.md"

assert_true test -f "$FILE"
assert_eq "$(bash scripts/ct-frontmatter.sh get "$FILE" maturity)" "draft"

for _ in 1 2 3 4; do
  bash scripts/ct-scoring.sh bump "$FILE" manual
done

IMPORTANCE=$(bash scripts/ct-frontmatter.sh get "$FILE" importance)
if [[ "$IMPORTANCE" =~ ^[0-9]+$ ]] && (( IMPORTANCE >= 85 )); then
  PASS=$((PASS + 1))
else
  echo "FAIL: importance did not reach core threshold (got $IMPORTANCE)"
  FAIL=$((FAIL + 1))
fi

assert_eq "$(bash scripts/ct-frontmatter.sh get "$FILE" maturity)" "core"

RECENCY=$(bash scripts/ct-frontmatter.sh get "$FILE" recency)
if [[ "$RECENCY" =~ ^[0-9]+\.[0-9]+$ ]]; then
  PASS=$((PASS + 1))
else
  echo "FAIL: recency is not numeric (got $RECENCY)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Scoring test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
