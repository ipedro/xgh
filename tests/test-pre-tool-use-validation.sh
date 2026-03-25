#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/pre-tool-use-preferences.sh"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

run_hook() {
  local input="$1"
  (cd "$REPO_ROOT" && echo "$input" | bash "$HOOK" 2>/dev/null) || true
}

make_input() {
  local cmd="$1"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd"
}

echo "=== test-pre-tool-use-validation ==="

# --- Check 1: Merge method (block severity) ---
echo "--- 1. Merge method mismatch (block) ---"
output=$(run_hook "$(make_input "gh pr merge 42 --merge")")
if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
  pass "merge method mismatch → deny"
else
  fail "merge method mismatch should deny. Output: $output"
fi

echo "--- 1b. Merge method match (pass-through) ---"
output=$(run_hook "$(make_input "gh pr merge 42 --squash")")
if [[ -z "$output" ]] || echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
  if [[ -z "$output" ]]; then
    pass "merge method match → silent pass-through"
  else
    fail "merge method match should pass through. Output: $output"
  fi
else
  pass "merge method match → no deny"
fi

# --- Check 2: Force-push on protected branch (block) ---
echo "--- 2. Force-push on protected branch (block) ---"
output=$(run_hook "$(make_input "git push origin main --force")")
if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
  pass "force-push to main → deny"
else
  fail "force-push to main should deny. Output: $output"
fi

echo "--- 2b. Force-push on non-protected branch ---"
output=$(run_hook "$(make_input "git push origin feat/foo --force")")
if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
  fail "force-push to feat/foo should not deny. Output: $output"
else
  pass "force-push to non-protected branch → pass-through"
fi

# --- Check 3: Branch naming convention (warn) ---
echo "--- 3. Branch naming (warn) ---"
output=$(run_hook "$(make_input "git checkout -b bad-branch-name")")
if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    fail "branch naming should warn, not deny. Output: $output"
  else
    pass "bad branch name → warn via additionalContext"
  fi
else
  fail "bad branch name should produce warning. Output: $output"
fi

echo "--- 3b. Branch naming match ---"
output=$(run_hook "$(make_input "git checkout -b feat/new-feature")")
if [[ -z "$output" ]]; then
  pass "valid branch name → silent pass-through"
else
  if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
    fail "valid branch name should not warn. Output: $output"
  else
    pass "valid branch name → no warning"
  fi
fi

echo "--- 3c. Branch naming with git switch -c ---"
output=$(run_hook "$(make_input "git switch -c bad-branch-name")")
if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  pass "git switch -c bad name → warn"
else
  fail "git switch -c bad name should warn. Output: $output"
fi

# --- Check 4: Protected branch (block) — direct commit ---
echo "--- 4. Commit on protected branch (block) ---"
output=$(run_hook "$(make_input "git commit -m 'test'")")
if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
  fail "commit on develop should not deny. Output: $output"
else
  pass "commit on non-protected branch → pass-through"
fi

# --- Check 5: Commit format (warn) ---
echo "--- 5. Commit format (warn) ---"
output=$(run_hook "$(make_input "git commit -m 'bad format no type prefix'")")
if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    fail "commit format should warn, not deny. Output: $output"
  else
    pass "bad commit format → warn"
  fi
else
  fail "bad commit format should warn. Output: $output"
fi

echo "--- 5b. Valid commit format ---"
output=$(run_hook "$(make_input "git commit -m 'feat: add new feature'")")
if [[ -z "$output" ]]; then
  pass "valid commit format → silent pass-through"
else
  if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
    ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""')
    if [[ "$ctx" == *"commit format"* ]] || [[ "$ctx" == *"commit_format"* ]]; then
      fail "valid commit format should not warn about format. Output: $output"
    else
      pass "valid commit format → no format warning"
    fi
  else
    pass "valid commit format → no warning"
  fi
fi

echo "--- 5c. Commit format with --message flag ---"
output=$(run_hook "$(make_input "git commit --message 'bad format'")")
if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  pass "git commit --message bad format → warn"
else
  fail "git commit --message bad format should warn. Output: $output"
fi

# --- Check 6: Non-matching command (pass-through) ---
echo "--- 6. Non-matching command ---"
output=$(run_hook "$(make_input "ls -la")")
if [[ -z "$output" ]]; then
  pass "non-matching command → silent pass-through"
else
  fail "non-matching command should produce no output. Output: $output"
fi

# --- Check 7: Non-Bash tool (early exit) ---
echo "--- 7. Non-Bash tool ---"
output=$(cd "$REPO_ROOT" && echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test"}}' | bash "$HOOK" 2>/dev/null || true)
if [[ -z "$output" ]]; then
  pass "non-Bash tool → silent exit"
else
  fail "non-Bash tool should produce no output. Output: $output"
fi

# --- Summary ---
echo ""
echo "PreToolUse validation: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
