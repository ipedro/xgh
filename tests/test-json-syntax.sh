#!/usr/bin/env bash
set -euo pipefail

# ── JSON Syntax Validation ───────────────────────────────
# Validates that all JSON files in the repository parse correctly.
# ─────────────────────────────────────────────────────────

PASS=0; FAIL=0

assert_json_valid() {
  local file="$1"
  if python3 -c "import json; json.load(open('$file'))" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $file is not valid JSON"
    FAIL=$((FAIL + 1))
  fi
}

# Find all JSON files, excluding .git
while IFS= read -r -d '' file; do
  assert_json_valid "$file"
done < <(find . -type f -name '*.json' -not -path './.git/*' -print0)

echo ""; echo "JSON syntax test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
