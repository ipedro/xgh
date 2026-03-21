#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0

assert_file_exists() {
  [[ -f "$1" ]] && PASS=$((PASS+1)) || { echo "FAIL: missing $1"; FAIL=$((FAIL+1)); }
}
assert_contains() {
  grep -qi "$2" "$1" 2>/dev/null && PASS=$((PASS+1)) || { echo "FAIL: $1 missing '$2'"; FAIL=$((FAIL+1)); }
}

assert_file_exists "skills/seed/seed.md"
assert_file_exists "commands/seed.md"

# Seed skill: reads context sources
assert_contains "skills/seed/seed.md" "context-tree"
assert_contains "skills/seed/seed.md" "detect-agents"
assert_contains "skills/seed/seed.md" "skill_dir"

# Seed skill: writes per-platform
assert_contains "skills/seed/seed.md" ".gemini/skills/xgh"
assert_contains "skills/seed/seed.md" ".agents/skills/xgh"
assert_contains "skills/seed/seed.md" ".opencode/skills/xgh"

# Seed skill: context content
assert_contains "skills/seed/seed.md" "context.md"
assert_contains "skills/seed/seed.md" "lossless-claude"

# commands/help.md
assert_contains "commands/help.md" "xgh-seed"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
