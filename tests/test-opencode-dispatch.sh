#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0

assert_file_exists() {
  [[ -f "$1" ]] && PASS=$((PASS+1)) || { echo "FAIL: missing $1"; FAIL=$((FAIL+1)); }
}
assert_contains() {
  grep -qi "$2" "$1" 2>/dev/null && PASS=$((PASS+1)) || { echo "FAIL: $1 missing '$2'"; FAIL=$((FAIL+1)); }
}

# File existence
assert_file_exists "skills/opencode/opencode.md"
assert_file_exists "commands/opencode.md"
assert_file_exists "tests/skill-triggering/prompts/opencode.txt"

# Skill: invocation pattern
assert_contains "skills/opencode/opencode.md" "opencode run"
assert_contains "skills/opencode/opencode.md" "Working directory"
assert_contains "skills/opencode/opencode.md" "non-interactive"

# Skill: dispatch types
assert_contains "skills/opencode/opencode.md" "exec"
assert_contains "skills/opencode/opencode.md" "review"

# Skill: isolation modes
assert_contains "skills/opencode/opencode.md" "worktree"
assert_contains "skills/opencode/opencode.md" "same-dir"

# Skill: output capture
assert_contains "skills/opencode/opencode.md" "output"
assert_contains "skills/opencode/opencode.md" "redirect"

# Skill: opencode reads .claude/skills
assert_contains "skills/opencode/opencode.md" ".claude/skills"

# Skill: model flag format
assert_contains "skills/opencode/opencode.md" "provider"

# Skill: background dispatch
assert_contains "skills/opencode/opencode.md" "run_in_background"

# agents.yaml
assert_contains "config/agents.yaml" "opencode run"

# commands/help.md
assert_contains "commands/help.md" "xgh-opencode"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
