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

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export XGH_CONTEXT_TREE="$TMPDIR/context-tree"

bash scripts/context-tree.sh init
bash scripts/context-tree.sh create "auth/oauth/callback.md" "OAuth Callback" "Handle oauth callback state and token exchange."
bash scripts/context-tree.sh create "database/indexing/btree.md" "BTree Indexing" "Database indexing and vacuum strategy."

SEARCH_JSON=$(bash scripts/context-tree.sh search "oauth callback state" 5)
TOP_PATH=$(python3 - "$SEARCH_JSON" <<'PY'
import json
import sys

rows = json.loads(sys.argv[1])
print(rows[0]["path"] if rows else "")
PY
)

assert_eq "$TOP_PATH" "auth/oauth/callback.md"

echo ""
echo "Search test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
