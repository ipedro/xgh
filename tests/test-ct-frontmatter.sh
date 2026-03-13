#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${SCRIPT_DIR}/scripts/ct-frontmatter.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); echo "FAIL: $label — expected '$expected', got '$actual'"
  fi
}

# --- ct_frontmatter_has ---
cat > "$TMP/with_fm.md" <<'EOF'
---
title: Test
importance: 50
---
Body content here
EOF

cat > "$TMP/no_fm.md" <<'EOF'
Just some text without frontmatter
EOF

if ct_frontmatter_has "$TMP/with_fm.md"; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1)); echo "FAIL: has: should detect frontmatter"
fi

if ct_frontmatter_has "$TMP/no_fm.md"; then
  FAIL=$((FAIL+1)); echo "FAIL: has: should reject file without frontmatter"
else
  PASS=$((PASS+1))
fi

# --- ct_frontmatter_get ---
assert_eq "get title" "Test" "$(ct_frontmatter_get "$TMP/with_fm.md" "title")"
assert_eq "get importance" "50" "$(ct_frontmatter_get "$TMP/with_fm.md" "importance")"
assert_eq "get missing key" "" "$(ct_frontmatter_get "$TMP/with_fm.md" "nonexistent" || true)"

# --- ct_frontmatter_set ---
ct_frontmatter_set "$TMP/with_fm.md" "importance" "75"
assert_eq "set importance" "75" "$(ct_frontmatter_get "$TMP/with_fm.md" "importance")"

# set new key
ct_frontmatter_set "$TMP/with_fm.md" "maturity" "validated"
assert_eq "set new key" "validated" "$(ct_frontmatter_get "$TMP/with_fm.md" "maturity")"

# body preserved after set
grep -q "Body content here" "$TMP/with_fm.md" && assert_eq "body preserved" "0" "0" || assert_eq "body preserved" "0" "1"

# updatedAt auto-set
UPDATED=$(ct_frontmatter_get "$TMP/with_fm.md" "updatedAt")
[ -n "$UPDATED" ] && assert_eq "updatedAt set" "0" "0" || assert_eq "updatedAt set" "0" "1"

# --- ct_frontmatter_increment_int ---
ct_frontmatter_set "$TMP/with_fm.md" "accessCount" "5"
ct_frontmatter_increment_int "$TMP/with_fm.md" "accessCount"
assert_eq "increment int" "6" "$(ct_frontmatter_get "$TMP/with_fm.md" "accessCount")"

# increment from 0
ct_frontmatter_set "$TMP/with_fm.md" "updateCount" "0"
ct_frontmatter_increment_int "$TMP/with_fm.md" "updateCount"
assert_eq "increment from 0" "1" "$(ct_frontmatter_get "$TMP/with_fm.md" "updateCount")"

# --- tags/keywords (array values) ---
cat > "$TMP/arrays.md" <<'EOF'
---
title: Arrays Test
tags: [auth, jwt]
keywords: [token, refresh]
---
EOF

assert_eq "get tags" "[auth, jwt]" "$(ct_frontmatter_get "$TMP/arrays.md" "tags")"
assert_eq "get keywords" "[token, refresh]" "$(ct_frontmatter_get "$TMP/arrays.md" "keywords")"

# --- quoted values ---
cat > "$TMP/quoted.md" <<'EOF'
---
title: "Quoted Title"
---
EOF

assert_eq "get quoted title" "Quoted Title" "$(ct_frontmatter_get "$TMP/quoted.md" "title")"

# --- get on file without frontmatter ---
assert_eq "get on no-fm file" "" "$(ct_frontmatter_get "$TMP/no_fm.md" "title" || true)"

# --- increment_int on missing key (should start at 0 → 1) ---
cat > "$TMP/missing_key.md" <<'EOF'
---
title: Missing Key Test
---
EOF

ct_frontmatter_increment_int "$TMP/missing_key.md" "accessCount"
assert_eq "increment missing key" "1" "$(ct_frontmatter_get "$TMP/missing_key.md" "accessCount")"

echo "Frontmatter tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
