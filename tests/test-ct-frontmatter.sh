#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1' — $3"; FAIL=$((FAIL+1)); fi
}
assert_contains() {
  if echo "$1" | grep -q "$2" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: output missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}
assert_file_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
source "${SCRIPT_DIR}/ct-frontmatter.sh"

# Setup temp dir
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# --- Test: write_frontmatter produces valid YAML frontmatter ---
cat > "${TMPDIR}/test1.md" <<'EOF'
## Raw Concept
Some content here.
EOF

write_frontmatter "${TMPDIR}/test1.md" \
  "title" "JWT Token Refresh" \
  "tags" "[auth, jwt]" \
  "keywords" "[refresh-token, rotation]" \
  "importance" "50" \
  "recency" "1.0" \
  "maturity" "draft" \
  "accessCount" "0" \
  "updateCount" "0" \
  "source" "auto-curate" \
  "fromAgent" "claude-code"

assert_file_contains "${TMPDIR}/test1.md" "^---" "frontmatter start delimiter"
assert_file_contains "${TMPDIR}/test1.md" "title: JWT Token Refresh" "title field"
assert_file_contains "${TMPDIR}/test1.md" "importance: 50" "importance field"
assert_file_contains "${TMPDIR}/test1.md" "maturity: draft" "maturity field"
assert_file_contains "${TMPDIR}/test1.md" "createdAt:" "createdAt auto-generated"
assert_file_contains "${TMPDIR}/test1.md" "updatedAt:" "updatedAt auto-generated"
assert_file_contains "${TMPDIR}/test1.md" "## Raw Concept" "body content preserved"

# --- Test: read_frontmatter_field extracts values ---
TITLE=$(read_frontmatter_field "${TMPDIR}/test1.md" "title")
assert_eq "$TITLE" "JWT Token Refresh" "read title"

IMPORTANCE=$(read_frontmatter_field "${TMPDIR}/test1.md" "importance")
assert_eq "$IMPORTANCE" "50" "read importance"

MATURITY=$(read_frontmatter_field "${TMPDIR}/test1.md" "maturity")
assert_eq "$MATURITY" "draft" "read maturity"

# --- Test: update_frontmatter_field changes a single field ---
update_frontmatter_field "${TMPDIR}/test1.md" "importance" "78"
NEW_IMP=$(read_frontmatter_field "${TMPDIR}/test1.md" "importance")
assert_eq "$NEW_IMP" "78" "updated importance"

# Body still intact
assert_file_contains "${TMPDIR}/test1.md" "## Raw Concept" "body after update"

# --- Test: read_frontmatter_body extracts body ---
BODY=$(read_frontmatter_body "${TMPDIR}/test1.md")
assert_contains "$BODY" "Some content here" "body extraction"

# --- Test: file without frontmatter ---
echo "Just plain content" > "${TMPDIR}/plain.md"
PLAIN_TITLE=$(read_frontmatter_field "${TMPDIR}/plain.md" "title")
assert_eq "$PLAIN_TITLE" "" "no frontmatter returns empty"

echo ""
echo "Frontmatter tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
