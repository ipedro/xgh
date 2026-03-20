#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_file_exists() {
  if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 missing"; FAIL=$((FAIL+1)); fi
}
assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 missing '$2'"; FAIL=$((FAIL+1)); fi
}
assert_executable() {
  if [ -x "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 not executable"; FAIL=$((FAIL+1)); fi
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# === mcp-detect.sh ===
assert_file_exists "${REPO_ROOT}/scripts/mcp-detect.sh"
assert_executable "${REPO_ROOT}/scripts/mcp-detect.sh"
assert_contains "${REPO_ROOT}/scripts/mcp-detect.sh" "detect_mcp"
assert_contains "${REPO_ROOT}/scripts/mcp-detect.sh" "slack"
assert_contains "${REPO_ROOT}/scripts/mcp-detect.sh" "figma"
assert_contains "${REPO_ROOT}/scripts/mcp-detect.sh" "atlassian"
assert_contains "${REPO_ROOT}/scripts/mcp-detect.sh" "lossless_claude"
assert_contains "${REPO_ROOT}/scripts/mcp-detect.sh" "XGH_AVAILABLE_MCPS"

# === briefing skill ===
assert_file_exists "${REPO_ROOT}/skills/briefing/briefing.md"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "xgh:briefing"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "NEEDS YOU NOW"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "IN PROGRESS"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "TEAM PULSE"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "SUGGESTED FOCUS"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "🐴🤖"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "XGH_BRIEFING"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "lcm_search"
assert_contains "${REPO_ROOT}/skills/briefing/briefing.md" "mcp-setup"

# === briefing command ===
assert_file_exists "${REPO_ROOT}/commands/briefing.md"
assert_contains "${REPO_ROOT}/commands/briefing.md" "xgh-briefing"
assert_contains "${REPO_ROOT}/commands/briefing.md" "compact"
assert_contains "${REPO_ROOT}/commands/briefing.md" "focus"

echo ""
echo "Briefing test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
