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

assert_not_exists() {
  if [[ ! -e "$1" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: expected path to be removed $1"
    FAIL=$((FAIL + 1))
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export XGH_CONTEXT_TREE="$TMPDIR/context-tree"

bash scripts/context-tree.sh init
bash scripts/context-tree.sh create "auth/jwt/legacy.md" "Legacy Flow" "Old draft flow"
bash scripts/context-tree.sh create "auth/jwt/current.md" "Current Flow" "Current validated flow"

LOW_FILE="$XGH_CONTEXT_TREE/auth/jwt/legacy.md"
HIGH_FILE="$XGH_CONTEXT_TREE/auth/jwt/current.md"

bash scripts/ct-frontmatter.sh set "$LOW_FILE" importance 20
bash scripts/ct-frontmatter.sh set "$LOW_FILE" maturity draft
bash scripts/ct-frontmatter.sh set "$HIGH_FILE" importance 90
bash scripts/ct-frontmatter.sh set "$HIGH_FILE" maturity core

ARCHIVED_COUNT=$(bash scripts/context-tree.sh archive)
if [[ "$ARCHIVED_COUNT" == "1" ]]; then
  PASS=$((PASS + 1))
else
  echo "FAIL: expected 1 archived file, got $ARCHIVED_COUNT"
  FAIL=$((FAIL + 1))
fi

assert_not_exists "$LOW_FILE"
assert_file_exists "$XGH_CONTEXT_TREE/_archived/auth/jwt/legacy.full.md"
assert_file_exists "$XGH_CONTEXT_TREE/_archived/auth/jwt/legacy.stub.md"
assert_file_exists "$HIGH_FILE"

bash scripts/context-tree.sh restore "_archived/auth/jwt/legacy.full.md" >/dev/null
assert_file_exists "$LOW_FILE"

echo ""
echo "Archive test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
