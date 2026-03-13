#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_contains() {
  if [[ "$1" == *"$2"* ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: expected '$2'"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  if [[ -f "$1" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: missing file $1"
    FAIL=$((FAIL + 1))
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export XGH_CONTEXT_TREE="$TMPDIR/context-tree"

bash scripts/context-tree.sh init
bash scripts/context-tree.sh create "auth/jwt/rotation.md" "Rotation" "Token rotation details"
bash scripts/context-tree.sh create "api/design/errors.md" "Errors" "Error envelope conventions"

bash scripts/ct-manifest.sh rebuild "$XGH_CONTEXT_TREE"
bash scripts/ct-manifest.sh update-indexes "$XGH_CONTEXT_TREE"

MANIFEST_LIST=$(bash scripts/ct-manifest.sh list "$XGH_CONTEXT_TREE")
assert_contains "$MANIFEST_LIST" "auth/jwt/rotation.md"
assert_contains "$MANIFEST_LIST" "api/design/errors.md"

assert_file_exists "$XGH_CONTEXT_TREE/_manifest.json"
assert_file_exists "$XGH_CONTEXT_TREE/_index.md"
assert_file_exists "$XGH_CONTEXT_TREE/auth/_index.md"
assert_file_exists "$XGH_CONTEXT_TREE/api/_index.md"

echo ""
echo "Manifest test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
