#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${SCRIPT_DIR}/scripts/ct-frontmatter.sh"
source "${SCRIPT_DIR}/scripts/ct-scoring.sh"
source "${SCRIPT_DIR}/scripts/ct-manifest.sh"
source "${SCRIPT_DIR}/scripts/ct-archive.sh"
source "${SCRIPT_DIR}/scripts/ct-search.sh"
source "${SCRIPT_DIR}/scripts/ct-sync.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS+1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL+1))
    echo "  FAIL: $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS+1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL+1))
    echo "  FAIL: $label"
    echo "    expected to contain: $needle"
    echo "    actual:              $haystack"
  fi
}

assert_file_exists() {
  local label="$1" file="$2"
  if [[ -f "$file" ]]; then
    PASS=$((PASS+1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL+1))
    echo "  FAIL: $label (file not found: $file)"
  fi
}

echo "=== ct-sync tests ==="

# --- slugify tests ---
echo "-- slugify --"

result=$(ct_sync_slugify "Hello World")
assert_eq "lowercase + spaces to hyphens" "hello-world" "$result"

result=$(ct_sync_slugify "JWT Auth Patterns!")
assert_eq "special chars removed" "jwt-auth-patterns" "$result"

result=$(ct_sync_slugify "  --Multiple---Hyphens--  ")
assert_eq "consecutive hyphens collapsed, leading/trailing stripped" "multiple-hyphens" "$result"

result=$(ct_sync_slugify "UPPERCASE_STRING")
assert_eq "uppercase with underscores" "uppercase-string" "$result"

# --- curate tests ---
echo "-- curate --"

ROOT="$TMP/ct"
mkdir -p "$ROOT"
ct_manifest_init "$ROOT"

ct_sync_curate "$ROOT" "backend" "auth" "JWT Best Practices" "This is about JWT." "" "" "" ""

expected_file="$ROOT/backend/auth/jwt-best-practices.md"
assert_file_exists "curate creates file at correct path" "$expected_file"

title_val=$(ct_frontmatter_get "$expected_file" "title")
assert_eq "frontmatter title set" "JWT Best Practices" "$title_val"

importance_val=$(ct_frontmatter_get "$expected_file" "importance")
assert_eq "default importance is 50" "50" "$importance_val"

maturity_val=$(ct_frontmatter_get "$expected_file" "maturity")
assert_eq "default maturity is draft" "draft" "$maturity_val"

# curate with tags and keywords
ct_sync_curate "$ROOT" "frontend" "react" "React Hooks Guide" "Hooks content." "state, hooks" "useState, useEffect" "" ""

hooks_file="$ROOT/frontend/react/react-hooks-guide.md"
assert_file_exists "curate with tags creates file" "$hooks_file"

tags_val=$(ct_frontmatter_get "$hooks_file" "tags")
assert_eq "tags stored as YAML array" "[state, hooks]" "$tags_val"

keywords_val=$(ct_frontmatter_get "$hooks_file" "keywords")
assert_eq "keywords stored as YAML array" "[useState, useEffect]" "$keywords_val"

# curate with source and from_agent
ct_sync_curate "$ROOT" "devops" "ci" "CI Pipeline Setup" "CI content." "" "" "manual" "cipher-agent"

ci_file="$ROOT/devops/ci/ci-pipeline-setup.md"
source_val=$(ct_frontmatter_get "$ci_file" "source")
assert_eq "source stored in frontmatter" "manual" "$source_val"

agent_val=$(ct_frontmatter_get "$ci_file" "from_agent")
assert_eq "from_agent stored in frontmatter" "cipher-agent" "$agent_val"

# verify manifest entry
manifest_list=$(ct_manifest_list "$ROOT")
assert_contains "manifest contains curated entry" "$manifest_list" "backend/auth/jwt-best-practices.md"

# --- query tests ---
echo "-- query --"

# ct_search_run requires bm25.py and actual content; test that query delegates correctly
# We test basic delegation - with empty query it should return []
result=$(ct_sync_query "$ROOT" "" "" "10")
assert_eq "empty query returns []" "[]" "$result"

# --- refresh tests ---
echo "-- refresh --"

ct_sync_refresh "$ROOT"
assert_file_exists "refresh creates _index.md for backend" "$ROOT/backend/_index.md"
assert_file_exists "refresh creates _index.md for frontend" "$ROOT/frontend/_index.md"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
