#!/usr/bin/env bash
set -euo pipefail

# ── Test Runner ──────────────────────────────────────────
# Discovers and runs all test-*.sh files in the tests/ directory.
# Exit code reflects overall pass/fail status.
#
# Usage:
#   bash tests/run-all.sh              # run all tests
#   bash tests/run-all.sh test-config  # run only test-config.sh
# ─────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0
FAILED_TESTS=()

# If arguments given, run only those test files
if [ $# -gt 0 ]; then
  TEST_FILES=()
  for arg in "$@"; do
    # Allow "test-config" or "test-config.sh" or "tests/test-config.sh"
    name="${arg##*/}"            # strip path
    name="${name%.sh}"           # strip .sh
    file="${SCRIPT_DIR}/${name}.sh"
    if [ -f "$file" ]; then
      TEST_FILES+=("$file")
    else
      echo -e "${RED}ERROR:${NC} test file not found: $file" >&2
      exit 1
    fi
  done
else
  mapfile -t TEST_FILES < <(find "$SCRIPT_DIR" -name 'test-*.sh' -type f | sort)
fi

echo ""
echo -e "${BOLD}🐴 xgh test runner${NC}"
echo -e "${DIM}Running ${#TEST_FILES[@]} test files${NC}"
echo ""

for test_file in "${TEST_FILES[@]}"; do
  test_name="$(basename "$test_file" .sh)"
  TOTAL=$((TOTAL + 1))

  # Run test and capture output + exit code
  output=""
  exit_code=0
  output=$(cd "$REPO_ROOT" && bash "$test_file" 2>&1) || exit_code=$?

  if [ $exit_code -eq 0 ]; then
    PASSED=$((PASSED + 1))
    # Extract pass count from output (last line usually has "N passed")
    summary=$(echo "$output" | grep -iE '(passed|PASS)' | tail -1)
    echo -e "  ${GREEN}✓${NC} ${test_name}  ${DIM}${summary}${NC}"
  else
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("$test_name")
    summary=$(echo "$output" | grep -iE '(failed|FAIL)' | tail -1)
    echo -e "  ${RED}✗${NC} ${test_name}  ${DIM}${summary}${NC}"
    # Show failure details indented
    echo "$output" | grep -i 'FAIL:' | while read -r line; do
      echo -e "    ${RED}${line}${NC}"
    done
  fi
done

echo ""
echo -e "${BOLD}━━━ Results ━━━${NC}"
echo -e "  Total:   ${TOTAL}"
echo -e "  ${GREEN}Passed:  ${PASSED}${NC}"
[ "$FAILED" -gt 0 ] && echo -e "  ${RED}Failed:  ${FAILED}${NC}" || echo -e "  Failed:  0"
[ "$SKIPPED" -gt 0 ] && echo -e "  ${YELLOW}Skipped: ${SKIPPED}${NC}"

if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo -e "${RED}Failed tests:${NC}"
  for t in "${FAILED_TESTS[@]}"; do
    echo -e "  ${RED}• ${t}${NC}"
  done
  echo ""
  exit 1
fi

echo ""
exit 0
