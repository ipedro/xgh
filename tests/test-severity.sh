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

# Source dependencies
REPO_ROOT="$(git rev-parse --show-toplevel)"
source "$REPO_ROOT/lib/preferences.sh"
source "$REPO_ROOT/lib/severity.sh"

# --- Test 1: Default severity for safety-critical checks ---
result=$(_severity_resolve "pr" "merge_method")
assert_equals "merge_method default severity" "block" "$result"

result=$(_severity_resolve "vcs" "force_push")
assert_equals "force_push default severity" "block" "$result"

result=$(_severity_resolve "vcs" "protected_branch")
assert_equals "protected_branch default severity" "block" "$result"

# --- Test 2: Default severity for convention checks ---
result=$(_severity_resolve "vcs" "branch_naming")
assert_equals "branch_naming default severity" "warn" "$result"

result=$(_severity_resolve "vcs" "commit_format")
assert_equals "commit_format default severity" "warn" "$result"

# --- Test 3: Unknown check falls back to warn ---
result=$(_severity_resolve "vcs" "nonexistent_check")
assert_equals "unknown check falls back to warn" "warn" "$result"

# --- Test 4: Configured severity overrides default ---
# Use a temp project.yaml where force_push (default=block) is set to warn
TMPYAML=$(mktemp)
cat > "$TMPYAML" << 'YAMEOF'
preferences:
  vcs:
    checks:
      force_push: { severity: warn }
YAMEOF
# Override _pref_project_yaml to point at temp file
_pref_project_yaml() { echo "$TMPYAML"; }
result=$(_severity_resolve "vcs" "force_push")
assert_equals "configured warn overrides default block" "warn" "$result"
# Restore original
_pref_project_yaml() {
  local root; root=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
  echo "$root/config/project.yaml"
}
rm -f "$TMPYAML"

# --- Test 5: Invalid configured severity falls back to default ---
TMPYAML2=$(mktemp)
cat > "$TMPYAML2" << 'YAMEOF'
preferences:
  vcs:
    checks:
      force_push: { severity: invalid_value }
YAMEOF
_pref_project_yaml() { echo "$TMPYAML2"; }
result=$(_severity_resolve "vcs" "force_push")
assert_equals "invalid severity falls back to default" "block" "$result"
_pref_project_yaml() {
  local root; root=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
  echo "$root/config/project.yaml"
}
rm -f "$TMPYAML2"

echo ""
echo "Severity test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
