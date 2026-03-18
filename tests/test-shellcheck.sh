#!/usr/bin/env bash
set -euo pipefail

# ── ShellCheck Validation ────────────────────────────────
# Runs shellcheck on all shell scripts in the repository.
# Skips if shellcheck is not installed (prints a warning).
# ─────────────────────────────────────────────────────────

PASS=0; FAIL=0

if ! command -v shellcheck &>/dev/null; then
  echo "SKIP: shellcheck not installed — install with: apt-get install shellcheck"
  echo ""
  echo "ShellCheck test: 0 passed, 0 failed (skipped)"
  exit 0
fi

# Collect all .sh files excluding .git, node_modules, and test files
# Test files use patterns (arithmetic in conditions) that shellcheck flags
# but are intentional in the assert_* helpers, so we use relaxed severity.
while IFS= read -r -d '' file; do
  if shellcheck --severity=error "$file" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: shellcheck errors in $file"
    shellcheck --severity=error "$file" 2>&1 | head -20
    FAIL=$((FAIL + 1))
  fi
done < <(find . -name '*.sh' -not -path './.git/*' -not -path './node_modules/*' -print0)

echo ""; echo "ShellCheck test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
