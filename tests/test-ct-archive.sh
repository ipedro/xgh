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

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="${REPO_ROOT}/scripts"
source "${SCRIPT_DIR}/ct-frontmatter.sh"
source "${SCRIPT_DIR}/ct-archive.sh"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

CT_DIR="${TMPDIR}/.xgh/context-tree"
mkdir -p "${CT_DIR}/authentication/jwt"
mkdir -p "${CT_DIR}/authentication/oauth"
export XGH_CONTEXT_TREE_DIR="$CT_DIR"

cat > "${CT_DIR}/_manifest.json" <<'EOF'
{"version":1,"team":"test","created":"2026-03-13T00:00:00Z","domains":[]}
EOF

cat > "${CT_DIR}/authentication/jwt/old-token-strategy.md" <<'EOF'
---
title: Old Token Strategy
tags: [auth, jwt]
keywords: [jwt]
importance: 20
recency: 0.1
maturity: draft
accessCount: 1
updateCount: 0
createdAt: 2026-01-01T00:00:00Z
updatedAt: 2026-01-15T00:00:00Z
source: auto-curate
fromAgent: test
---

This is an old strategy that is no longer used.
It has detailed implementation notes here.
EOF

cat > "${CT_DIR}/authentication/jwt/current-strategy.md" <<'EOF'
---
title: Current JWT Strategy
tags: [auth, jwt]
keywords: [jwt, current]
importance: 80
recency: 0.9
maturity: validated
accessCount: 15
updateCount: 5
createdAt: 2026-02-01T00:00:00Z
updatedAt: 2026-03-10T00:00:00Z
source: manual
fromAgent: test
---

Current active strategy with high importance.
EOF

cat > "${CT_DIR}/authentication/oauth/unused-flow.md" <<'EOF'
---
title: Unused OAuth Flow
tags: [auth, oauth]
keywords: [oauth, unused]
importance: 15
recency: 0.05
maturity: draft
accessCount: 0
updateCount: 0
createdAt: 2025-12-01T00:00:00Z
updatedAt: 2025-12-15T00:00:00Z
source: auto-curate
fromAgent: test
---

An OAuth flow that was never used. Contains implementation details.
EOF

# --- Test: archive_stale archives draft files with importance < 35 ---
archive_stale "$CT_DIR" 35

assert_file_not_exists "${CT_DIR}/authentication/jwt/old-token-strategy.md" "original file removed"
assert_file_exists "${CT_DIR}/_archived/authentication/jwt/old-token-strategy.full.md" "full backup exists"
assert_file_exists "${CT_DIR}/authentication/jwt/old-token-strategy.stub.md" "stub exists in original location"

assert_file_contains "${CT_DIR}/authentication/jwt/old-token-strategy.stub.md" "title: Old Token Strategy" "stub has title"
assert_file_contains "${CT_DIR}/authentication/jwt/old-token-strategy.stub.md" "archived: true" "stub has archived flag"
assert_file_contains "${CT_DIR}/authentication/jwt/old-token-strategy.stub.md" "ARCHIVED" "stub body says ARCHIVED"

assert_file_contains "${CT_DIR}/_archived/authentication/jwt/old-token-strategy.full.md" "detailed implementation notes" "full backup has body"

assert_file_exists "${CT_DIR}/authentication/jwt/current-strategy.md" "high-importance file untouched"

assert_file_not_exists "${CT_DIR}/authentication/oauth/unused-flow.md" "unused flow removed"
assert_file_exists "${CT_DIR}/_archived/authentication/oauth/unused-flow.full.md" "unused flow backup"
assert_file_exists "${CT_DIR}/authentication/oauth/unused-flow.stub.md" "unused flow stub"

# --- Test: restore_archived restores a file from archive ---
restore_archived "$CT_DIR" "authentication/jwt/old-token-strategy"

assert_file_exists "${CT_DIR}/authentication/jwt/old-token-strategy.md" "restored file exists"
assert_file_not_exists "${CT_DIR}/authentication/jwt/old-token-strategy.stub.md" "stub removed after restore"
assert_file_not_exists "${CT_DIR}/_archived/authentication/jwt/old-token-strategy.full.md" "archive backup removed after restore"
assert_file_contains "${CT_DIR}/authentication/jwt/old-token-strategy.md" "detailed implementation notes" "restored content intact"

echo ""
echo "Archive tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
