#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1' — $3"; FAIL=$((FAIL+1)); fi
}
assert_file_exists() {
  if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 missing — $2"; FAIL=$((FAIL+1)); fi
}
assert_file_not_exists() {
  if [ ! -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 should not exist — $2"; FAIL=$((FAIL+1)); fi
}
assert_file_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}
assert_dir_exists() {
  if [ -d "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: dir $1 missing — $2"; FAIL=$((FAIL+1)); fi
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CT_SCRIPT="${REPO_ROOT}/scripts/context-tree.sh"

# Setup temp project dir
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Initialize a minimal context tree
CT_DIR="${TMPDIR}/.xgh/context-tree"
mkdir -p "$CT_DIR"
cat > "${CT_DIR}/_manifest.json" <<'EOF'
{
  "version": 1,
  "team": "test-team",
  "created": "2026-03-13T00:00:00Z",
  "domains": []
}
EOF

export XGH_CONTEXT_TREE_DIR="$CT_DIR"

# --- Test: create a knowledge file ---
bash "$CT_SCRIPT" create \
  --domain "authentication" \
  --topic "jwt-implementation" \
  --title "JWT Token Refresh Strategy" \
  --tags "auth,jwt,security" \
  --keywords "refresh-token,rotation,expiry" \
  --source "auto-curate" \
  --from-agent "claude-code" \
  --body "## Raw Concept
Tokens should rotate on every refresh call.

## Facts
- category: convention
  fact: Refresh tokens rotate on every use"

EXPECTED_FILE="${CT_DIR}/authentication/jwt-implementation/jwt-token-refresh-strategy.md"
assert_file_exists "$EXPECTED_FILE" "created knowledge file"
assert_file_contains "$EXPECTED_FILE" "title: JWT Token Refresh Strategy" "title in frontmatter"
assert_file_contains "$EXPECTED_FILE" "tags: \[auth, jwt, security\]" "tags in frontmatter"
assert_file_contains "$EXPECTED_FILE" "importance: 10" "initial importance is 10"
assert_file_contains "$EXPECTED_FILE" "recency: 1.0" "initial recency is 1.0"
assert_file_contains "$EXPECTED_FILE" "maturity: draft" "initial maturity is draft"
assert_file_contains "$EXPECTED_FILE" "accessCount: 0" "initial accessCount"
assert_file_contains "$EXPECTED_FILE" "updateCount: 0" "initial updateCount"
assert_file_contains "$EXPECTED_FILE" "Tokens should rotate" "body content"
assert_dir_exists "${CT_DIR}/authentication/jwt-implementation" "topic dir created"

# --- Test: create with subtopic ---
bash "$CT_SCRIPT" create \
  --domain "authentication" \
  --topic "jwt-implementation" \
  --subtopic "refresh-tokens" \
  --title "Token Rotation Policy" \
  --tags "auth,jwt" \
  --keywords "rotation" \
  --source "manual" \
  --from-agent "claude-code" \
  --body "Rotate on every use."

SUBTOPIC_FILE="${CT_DIR}/authentication/jwt-implementation/refresh-tokens/token-rotation-policy.md"
assert_file_exists "$SUBTOPIC_FILE" "subtopic file created"

# --- Test: read a knowledge file ---
READ_OUTPUT=$(bash "$CT_SCRIPT" read --path "authentication/jwt-implementation/jwt-token-refresh-strategy")
assert_eq "$?" "0" "read exits 0"
echo "$READ_OUTPUT" | grep -q "JWT Token Refresh Strategy" && PASS=$((PASS+1)) || { echo "FAIL: read output missing title"; FAIL=$((FAIL+1)); }
echo "$READ_OUTPUT" | grep -q "Tokens should rotate" && PASS=$((PASS+1)) || { echo "FAIL: read output missing body"; FAIL=$((FAIL+1)); }

# --- Test: read bumps accessCount ---
bash "$CT_SCRIPT" read --path "authentication/jwt-implementation/jwt-token-refresh-strategy" > /dev/null
ACCESS=$(grep "accessCount:" "$EXPECTED_FILE" | head -1 | awk '{print $2}')
assert_eq "$ACCESS" "2" "accessCount bumped to 2"

# --- Test: list files ---
LIST_OUTPUT=$(bash "$CT_SCRIPT" list)
echo "$LIST_OUTPUT" | grep -q "jwt-token-refresh-strategy" && PASS=$((PASS+1)) || { echo "FAIL: list missing file"; FAIL=$((FAIL+1)); }
echo "$LIST_OUTPUT" | grep -q "token-rotation-policy" && PASS=$((PASS+1)) || { echo "FAIL: list missing subtopic file"; FAIL=$((FAIL+1)); }

# --- Test: list with domain filter ---
LIST_AUTH=$(bash "$CT_SCRIPT" list --domain "authentication")
echo "$LIST_AUTH" | grep -q "jwt-token-refresh-strategy" && PASS=$((PASS+1)) || { echo "FAIL: filtered list missing file"; FAIL=$((FAIL+1)); }

# --- Test: update a knowledge file ---
bash "$CT_SCRIPT" update \
  --path "authentication/jwt-implementation/jwt-token-refresh-strategy" \
  --body "## Raw Concept
Tokens should rotate on every refresh call. Added: 7-day absolute expiry.

## Facts
- category: convention
  fact: Refresh tokens rotate on every use with 7-day expiry"

assert_file_contains "$EXPECTED_FILE" "7-day absolute expiry" "updated body"
UCOUNT=$(grep "updateCount:" "$EXPECTED_FILE" | head -1 | awk '{print $2}')
assert_eq "$UCOUNT" "1" "updateCount bumped"

# --- Test: update tags ---
bash "$CT_SCRIPT" update \
  --path "authentication/jwt-implementation/jwt-token-refresh-strategy" \
  --tags "auth,jwt,security,token-rotation"

assert_file_contains "$EXPECTED_FILE" "token-rotation" "updated tags"

# --- Test: delete a knowledge file ---
bash "$CT_SCRIPT" delete --path "authentication/jwt-implementation/refresh-tokens/token-rotation-policy"
assert_file_not_exists "$SUBTOPIC_FILE" "deleted file"

# --- Test: create with duplicate title in same location fails ---
bash "$CT_SCRIPT" create \
  --domain "authentication" \
  --topic "jwt-implementation" \
  --title "JWT Token Refresh Strategy" \
  --tags "auth" \
  --keywords "jwt" \
  --source "manual" \
  --from-agent "claude-code" \
  --body "Duplicate." 2>/dev/null && {
    echo "FAIL: duplicate create should fail"; FAIL=$((FAIL+1))
  } || PASS=$((PASS+1))

echo ""
echo "CRUD tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
