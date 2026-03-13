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
    echo "FAIL: path still exists $1"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  if [[ "$1" == *"$2"* ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: expected to find '$2'"
    FAIL=$((FAIL + 1))
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export XGH_CONTEXT_TREE="$TMPDIR/context-tree"

bash scripts/context-tree.sh init
bash scripts/context-tree.sh create "auth/jwt/rotation.md" "Rotation Strategy" "Refresh tokens rotate at each use."

assert_file_exists "$XGH_CONTEXT_TREE/auth/jwt/rotation.md"

LIST_OUTPUT=$(bash scripts/context-tree.sh list)
assert_contains "$LIST_OUTPUT" "auth/jwt/rotation.md"

READ_OUTPUT=$(bash scripts/context-tree.sh read "auth/jwt/rotation.md")
assert_contains "$READ_OUTPUT" "Rotation Strategy"

bash scripts/context-tree.sh update "auth/jwt/rotation.md" "Absolute expiry is 7 days."
UPDATED_OUTPUT=$(bash scripts/context-tree.sh read "auth/jwt/rotation.md")
assert_contains "$UPDATED_OUTPUT" "Absolute expiry is 7 days."

bash scripts/context-tree.sh delete "auth/jwt/rotation.md"
assert_not_exists "$XGH_CONTEXT_TREE/auth/jwt/rotation.md"

echo ""
echo "Context tree core test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
