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

bash scripts/ct-sync.sh curate --root "$XGH_CONTEXT_TREE" --domain "Auth" --topic "JWT" --title "Token Rotation" --content "Rotate refresh tokens and enforce absolute expiry." >/dev/null
bash scripts/ct-sync.sh curate --root "$XGH_CONTEXT_TREE" --domain "API" --topic "Errors" --title "Error Envelope" --content "All API errors include code and trace id." >/dev/null

assert_true test -f "$XGH_CONTEXT_TREE/auth/jwt/token-rotation.md"
assert_true test -f "$XGH_CONTEXT_TREE/api/errors/error-envelope.md"

bash scripts/context-tree.sh score "auth/jwt/token-rotation.md" manual

SEARCH_JSON=$(bash scripts/context-tree.sh search "refresh token expiry" 5)
TOP_PATH=$(python3 - "$SEARCH_JSON" <<'PY'
import json
import sys
rows = json.loads(sys.argv[1])
print(rows[0]["path"] if rows else "")
PY
)
assert_contains "$TOP_PATH" "auth/jwt/token-rotation.md"

bash scripts/ct-frontmatter.sh set "$XGH_CONTEXT_TREE/api/errors/error-envelope.md" importance 10
bash scripts/ct-frontmatter.sh set "$XGH_CONTEXT_TREE/api/errors/error-envelope.md" maturity draft
ARCHIVE_COUNT=$(bash scripts/context-tree.sh archive)
assert_contains "$ARCHIVE_COUNT" "1"

MANIFEST_LIST=$(bash scripts/ct-manifest.sh list "$XGH_CONTEXT_TREE")
assert_contains "$MANIFEST_LIST" "auth/jwt/token-rotation.md"

echo ""
echo "Context tree integration test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
