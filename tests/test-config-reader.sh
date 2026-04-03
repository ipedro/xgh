#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_equals() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected '$expected', got '$actual'"
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

# --- Source the library ---
assert_contains "lib/config-reader.sh" "load_pr_pref"
assert_contains "lib/config-reader.sh" "probe_pr_field"
assert_contains "lib/config-reader.sh" "cache_pr_pref"

# --- Functional tests using real project.yaml ---
source lib/config-reader.sh

# CLI override wins
result=$(load_pr_pref "provider" "gitlab" "")
assert_equals "CLI override wins" "gitlab" "$result"

# Project default (no CLI override, no branch)
result=$(load_pr_pref "provider" "" "")
assert_equals "Project default: provider" "github" "$result"

result=$(load_pr_pref "repo" "" "")
assert_equals "Project default: repo" "tokyo-megacorp/xgh" "$result"

result=$(load_pr_pref "reviewer" "" "")
assert_equals "Project default: reviewer" "copilot-pull-request-reviewer[bot]" "$result"

result=$(load_pr_pref "reviewer_comment_author" "" "")
assert_equals "Project default: reviewer_comment_author" "Copilot" "$result"

result=$(load_pr_pref "merge_method" "" "")
assert_equals "Project default: merge_method" "squash" "$result"

# Branch-specific override
result=$(load_pr_pref "merge_method" "" "main")
assert_equals "Branch override: main merge_method" "merge" "$result"

result=$(load_pr_pref "merge_method" "" "develop")
assert_equals "Branch override: develop merge_method" "squash" "$result"

# CLI override beats branch override
result=$(load_pr_pref "merge_method" "rebase" "main")
assert_equals "CLI beats branch" "rebase" "$result"

# Branch override for non-merge_method field
result=$(load_pr_pref "required_approvals" "" "main")
assert_equals "Branch override: main required_approvals" "1" "$result"

# Boolean field (review_on_push)
result=$(load_pr_pref "review_on_push" "" "")
assert_equals "Boolean field: review_on_push" "true" "$result"

# Unset field returns empty
result=$(load_pr_pref "nonexistent_field" "" "")
assert_equals "Unset field returns empty" "" "$result"

echo ""
echo "Config reader test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
