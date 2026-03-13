#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_not_exists() {
  if [ ! -e "$1" ]; then PASS=$((PASS + 1)); else echo "FAIL: $1 still exists"; FAIL=$((FAIL + 1)); fi
}

assert_not_contains() {
  if ! grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS + 1)); else echo "FAIL: $1 still contains '$2'"; FAIL=$((FAIL + 1)); fi
}

# Setup: install first, then uninstall
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT
cd "$TMPDIR"
git init --quiet

export XGH_DRY_RUN=1
export XGH_TEAM="test-team"
export XGH_LOCAL_PACK="$(cd - >/dev/null && pwd)"

# Install
bash "${XGH_LOCAL_PACK}/install.sh" >/dev/null 2>&1

# Uninstall
bash "${XGH_LOCAL_PACK}/uninstall.sh"

# Verify removal
assert_not_exists ".claude/hooks/xgh-session-start.sh"
assert_not_exists ".claude/hooks/xgh-prompt-submit.sh"
assert_not_exists ".claude/.mcp.json"

# CLAUDE.local.md should have xgh section removed
if [ -f "CLAUDE.local.md" ]; then
  assert_not_contains "CLAUDE.local.md" "mcs:begin xgh"
fi

echo ""
echo "Uninstall test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
