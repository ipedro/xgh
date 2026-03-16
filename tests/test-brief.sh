#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0

assert_file_exists() {
  if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 missing"; FAIL=$((FAIL+1)); fi
}

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 missing '$2'"; FAIL=$((FAIL+1)); fi
}

assert_executable() {
  if [ -x "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 not executable"; FAIL=$((FAIL+1)); fi
}

# ── Task 1: mcp-detect.sh ────────────────────────────────────────────────────

assert_file_exists "$REPO_ROOT/scripts/mcp-detect.sh"
assert_executable  "$REPO_ROOT/scripts/mcp-detect.sh"

# Must define detection functions
assert_contains "$REPO_ROOT/scripts/mcp-detect.sh" "xgh_has_slack"
assert_contains "$REPO_ROOT/scripts/mcp-detect.sh" "xgh_has_jira"
assert_contains "$REPO_ROOT/scripts/mcp-detect.sh" "xgh_has_github"
assert_contains "$REPO_ROOT/scripts/mcp-detect.sh" "xgh_has_cipher"

# Must use sourcing guard (not execute-only)
assert_contains "$REPO_ROOT/scripts/mcp-detect.sh" "XGH_MCP_DETECT_LOADED"

# ── Task 3: briefing command ─────────────────────────────────────────────────

assert_file_exists "$REPO_ROOT/commands/brief.md"

# YAML frontmatter
assert_contains "$REPO_ROOT/commands/brief.md" "name: xgh-brief"
assert_contains "$REPO_ROOT/commands/brief.md" "description:"

# Invokes the briefing skill
assert_contains "$REPO_ROOT/commands/brief.md" "xgh:briefing"

# ── Task 4: session-start hook XGH_BRIEFING support ─────────────────────────

assert_contains "$REPO_ROOT/hooks/session-start.sh" "XGH_BRIEFING"

# Hook must still output JSON with result key
assert_contains "$REPO_ROOT/hooks/session-start.sh" '"result"'

# ── Task 5: techpack.yaml briefing entries ───────────────────────────────────

assert_contains "$REPO_ROOT/techpack.yaml" "briefing"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "Briefing test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
