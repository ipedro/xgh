#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_file_exists() {
  if [[ -f "$1" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: missing file $1"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  if grep -qi "$2" "$1" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 missing '$2'"
    FAIL=$((FAIL + 1))
  fi
}

# --- File existence ---
assert_file_exists "skills/gemini/gemini.md"
assert_file_exists "commands/gemini.md"
assert_file_exists "tests/skill-triggering/prompts/gemini.txt"

# --- Skill content ---
assert_contains "skills/gemini/gemini.md" "gemini"
assert_contains "skills/gemini/gemini.md" "worktree"
assert_contains "skills/gemini/gemini.md" "same-dir"
assert_contains "skills/gemini/gemini.md" "yolo"
assert_contains "skills/gemini/gemini.md" "approval-mode plan"
assert_contains "skills/gemini/gemini.md" "run_in_background"
assert_contains "skills/gemini/gemini.md" "lossless-claude"
assert_contains "skills/gemini/gemini.md" "headless"

# --- Command content ---
assert_contains "commands/gemini.md" "xgh:gemini"
assert_contains "commands/gemini.md" "/xgh-gemini"
assert_contains "commands/gemini.md" "exec"
assert_contains "commands/gemini.md" "review"

# --- Agents.yaml gemini entry ---
assert_contains "config/agents.yaml" "gemini:"
assert_contains "config/agents.yaml" "yolo"
assert_contains "config/agents.yaml" "approval-mode plan"

# --- Help command references gemini ---
assert_contains "commands/help.md" "/xgh-gemini"

echo ""
echo "Gemini dispatch test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
