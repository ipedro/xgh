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

ROOT="$TMPDIR/context-tree"

PATH_ONE=$(bash scripts/ct-sync.sh curate --root "$ROOT" --domain "Auth" --topic "JWT" --title "Refresh Rotation" --content "Rotate refresh tokens each time they are used.")
assert_eq "$PATH_ONE" "auth/jwt/refresh-rotation.md"

PATH_TWO=$(bash scripts/ct-sync.sh curate --root "$ROOT" --domain "Auth" --topic "JWT" --title "Refresh Rotation" --content "Absolute expiry is seven days.")
assert_eq "$PATH_TWO" "auth/jwt/refresh-rotation.md"

CONTENT=$(cat "$ROOT/auth/jwt/refresh-rotation.md")
assert_contains "$CONTENT" "Absolute expiry is seven days."

QUERY_JSON=$(bash scripts/ct-sync.sh query --root "$ROOT" --query "refresh tokens" --top 5)
RESULT_PATH=$(python3 - "$QUERY_JSON" <<'PY'
import json
import sys
rows = json.loads(sys.argv[1])
print(rows[0]["path"] if rows else "")
PY
)

assert_eq "$RESULT_PATH" "auth/jwt/refresh-rotation.md"

echo ""
echo "Sync test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
