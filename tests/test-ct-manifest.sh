#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1' — $3"; FAIL=$((FAIL+1)); fi
}
assert_contains() {
  if echo "$1" | grep -q "$2" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: output missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}
assert_file_exists() {
  if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 missing — $2"; FAIL=$((FAIL+1)); fi
}
assert_file_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CT_SCRIPT="${REPO_ROOT}/scripts/context-tree.sh"
SCRIPT_DIR="${REPO_ROOT}/scripts"
source "${SCRIPT_DIR}/ct-frontmatter.sh"
source "${SCRIPT_DIR}/ct-manifest.sh"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

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

bash "$CT_SCRIPT" create \
  --domain "authentication" --topic "jwt" \
  --title "JWT Token Refresh" --tags "auth,jwt" --keywords "jwt,refresh" \
  --source "manual" --from-agent "test" --body "JWT refresh strategy."

bash "$CT_SCRIPT" create \
  --domain "authentication" --topic "oauth" \
  --title "OAuth2 Flow" --tags "auth,oauth" --keywords "oauth2" \
  --source "manual" --from-agent "test" --body "OAuth2 authorization code flow."

bash "$CT_SCRIPT" create \
  --domain "api-design" --topic "rest" \
  --title "REST Conventions" --tags "api,rest" --keywords "rest,conventions" \
  --source "manual" --from-agent "test" --body "Use kebab-case for URLs."

# --- Test: rebuild_manifest creates valid manifest ---
rebuild_manifest "$CT_DIR"

python3 -c "import json; json.load(open('${CT_DIR}/_manifest.json'))" && PASS=$((PASS+1)) || { echo "FAIL: manifest invalid JSON"; FAIL=$((FAIL+1)); }

MANIFEST=$(cat "${CT_DIR}/_manifest.json")
assert_contains "$MANIFEST" "authentication" "manifest has authentication domain"
assert_contains "$MANIFEST" "api-design" "manifest has api-design domain"

assert_contains "$MANIFEST" "jwt-token-refresh" "manifest has JWT entry"
assert_contains "$MANIFEST" "oauth2-flow" "manifest has OAuth entry"
assert_contains "$MANIFEST" "rest-conventions" "manifest has REST entry"

ENTRY_COUNT=$(python3 -c "
import json
m = json.load(open('${CT_DIR}/_manifest.json'))
total = sum(len(d.get('entries', [])) for d in m.get('domains', []))
print(total)
")
assert_eq "$ENTRY_COUNT" "3" "manifest has 3 total entries"

# --- Test: generate_index creates _index.md per domain ---
generate_index "$CT_DIR"
assert_file_exists "${CT_DIR}/authentication/_index.md" "auth domain _index.md"
assert_file_exists "${CT_DIR}/api-design/_index.md" "api-design domain _index.md"

assert_file_contains "${CT_DIR}/authentication/_index.md" "JWT Token Refresh" "index has JWT title"
assert_file_contains "${CT_DIR}/authentication/_index.md" "OAuth2 Flow" "index has OAuth title"
assert_file_contains "${CT_DIR}/api-design/_index.md" "REST Conventions" "index has REST title"

# --- Test: add_to_manifest adds a single entry ---
bash "$CT_SCRIPT" create \
  --domain "authentication" --topic "sessions" \
  --title "Session Management" --tags "auth,sessions" --keywords "sessions" \
  --source "manual" --from-agent "test" --body "Cookie-based sessions."

add_to_manifest "$CT_DIR" "authentication/sessions/session-management.md" "Session Management" "draft" "10"

MANIFEST2=$(cat "${CT_DIR}/_manifest.json")
assert_contains "$MANIFEST2" "session-management" "added entry in manifest"

# --- Test: remove_from_manifest removes an entry ---
remove_from_manifest "$CT_DIR" "authentication/sessions/session-management.md"
MANIFEST3=$(cat "${CT_DIR}/_manifest.json")
echo "$MANIFEST3" | grep -q "session-management" && { echo "FAIL: entry should be removed"; FAIL=$((FAIL+1)); } || PASS=$((PASS+1))

echo ""
echo "Manifest tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
