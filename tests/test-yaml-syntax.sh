#!/usr/bin/env bash
set -euo pipefail

# ── YAML Syntax Validation ───────────────────────────────
# Validates that all YAML files in the repository parse correctly.
# ─────────────────────────────────────────────────────────

PASS=0; FAIL=0

assert_yaml_valid() {
  local file="$1"
  if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $file is not valid YAML"
    FAIL=$((FAIL + 1))
  fi
}

# Find all YAML files, excluding .git
while IFS= read -r -d '' file; do
  assert_yaml_valid "$file"
done < <(find . -type f \( -name '*.yaml' -o -name '*.yml' \) -not -path './.git/*' -print0)

echo ""; echo "YAML syntax test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
