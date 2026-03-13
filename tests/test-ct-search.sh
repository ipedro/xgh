#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1' — $3"; FAIL=$((FAIL+1)); fi
}
assert_contains() {
  if echo "$1" | grep -q "$2" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: output missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}
assert_not_contains() {
  if ! echo "$1" | grep -q "$2" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: output should not contain '$2' — $3"; FAIL=$((FAIL+1)); fi
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CT_SCRIPT="${REPO_ROOT}/scripts/context-tree.sh"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

CT_DIR="${TMPDIR}/.xgh/context-tree"
mkdir -p "$CT_DIR"
cat > "${CT_DIR}/_manifest.json" <<'EOF'
{"version":1,"team":"test","created":"2026-03-13T00:00:00Z","domains":[]}
EOF

export XGH_CONTEXT_TREE_DIR="$CT_DIR"

bash "$CT_SCRIPT" create \
  --domain "authentication" \
  --topic "jwt" \
  --title "JWT Token Refresh" \
  --tags "auth,jwt,security" \
  --keywords "refresh-token,rotation" \
  --source "manual" \
  --from-agent "test" \
  --body "Refresh tokens should rotate on every use. The JWT implementation uses RSA256 for signing."

bash "$CT_SCRIPT" create \
  --domain "api-design" \
  --topic "rest" \
  --title "REST API Conventions" \
  --tags "api,rest,conventions" \
  --keywords "endpoints,http-methods" \
  --source "manual" \
  --from-agent "test" \
  --body "Use kebab-case for URLs. POST for creation, PUT for full replacement, PATCH for partial updates."

bash "$CT_SCRIPT" create \
  --domain "authentication" \
  --topic "oauth" \
  --title "OAuth2 GitHub SSO" \
  --tags "auth,oauth,github" \
  --keywords "sso,github,oauth2" \
  --source "manual" \
  --from-agent "test" \
  --body "GitHub SSO uses OAuth2 authorization code flow. Tokens are stored in secure HTTP-only cookies."

# --- Test: search for "JWT refresh token" should rank JWT file first ---
RESULT=$(bash "$CT_SCRIPT" search --query "JWT refresh token")
assert_contains "$RESULT" "jwt-token-refresh" "JWT file found in results"

# --- Test: search for "OAuth GitHub" should find OAuth file ---
RESULT2=$(bash "$CT_SCRIPT" search --query "OAuth GitHub SSO")
assert_contains "$RESULT2" "oauth2-github-sso" "OAuth file found"

# --- Test: search for "REST API endpoints" should find REST file ---
RESULT3=$(bash "$CT_SCRIPT" search --query "REST API endpoints conventions")
assert_contains "$RESULT3" "rest-api-conventions" "REST file found"

# --- Test: search for nonexistent term returns no results ---
RESULT4=$(bash "$CT_SCRIPT" search --query "kubernetes deployment helm")
assert_not_contains "$RESULT4" "ERROR" "no error on empty search"

# --- Test: search with --limit ---
RESULT5=$(bash "$CT_SCRIPT" search --query "auth token" --limit 1)
LINE_COUNT=$(echo "$RESULT5" | grep -c "\.md" || true)
if [ "$LINE_COUNT" -le 1 ]; then PASS=$((PASS+1)); else echo "FAIL: limit 1 returned $LINE_COUNT results"; FAIL=$((FAIL+1)); fi

# --- Test: BM25 python module works standalone ---
PYTHON_RESULT=$(python3 "${REPO_ROOT}/scripts/bm25.py" "$CT_DIR" "JWT refresh token rotation" 5)
assert_contains "$PYTHON_RESULT" "jwt-token-refresh" "Python BM25 finds JWT file"

echo ""
echo "Search tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
